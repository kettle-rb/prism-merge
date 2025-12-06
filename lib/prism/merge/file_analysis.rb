# frozen_string_literal: true

module Prism
  module Merge
    # Simplified file analysis using Prism's native comment attachment.
    # This version leverages parse_result.attach_comments! to automatically
    # attach comments to nodes, eliminating the need for manual comment tracking
    # and the CommentNode class.
    #
    # Key improvements over V1:
    # - Uses Prism's native node.location.leading_comments and trailing_comments
    # - No manual comment tracking or CommentNode class
    # - Simpler freeze block extraction via comment scanning
    # - Better performance (one attach_comments! call vs multiple iterations)
    # - Enhanced freeze block validation (detects partial nodes and non-class/module contexts)
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      DEFAULT_FREEZE_TOKEN = "prism-merge"

      # @return [Prism::ParseResult] The parse result from Prism
      attr_reader :parse_result

      # Initialize file analysis with Prism's native comment handling
      #
      # @param source [String] Ruby source code to analyze
      # @param freeze_token [String] Token for freeze block markers (default: "prism-merge")
      # @param signature_generator [Proc, nil] Custom signature generator
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil)
        @source = source
        @lines = source.lines
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @parse_result = DebugLogger.time("FileAnalysis#parse") { Prism.parse(source) }

        # Use Prism's native comment attachment
        # On JRuby, the Comments class may not be loaded yet, so we need to require it
        attach_comments_safely!

        # Extract and validate structure
        @statements = extract_and_integrate_all_nodes

        DebugLogger.debug("FileAnalysis initialized", {
          signature_generator: signature_generator ? "custom" : "default",
          statements_count: @statements.size,
          freeze_blocks: freeze_blocks.size,
        })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @parse_result.success?
      end

      # Get nodes with their associated comments and metadata
      # Comments are now accessed via Prism's native node.location API
      # @return [Array<Hash>] Array of node info hashes
      def nodes_with_comments
        @nodes_with_comments ||= extract_nodes_with_comments
      end

      # Generate signature for a node.
      #
      # If a custom signature_generator is provided, it is called first. The custom
      # generator can return:
      # - An array signature (e.g., `[:gem, "foo"]`) - used as the signature
      # - `nil` - the node gets no signature (won't be matched by signature)
      # - A `Prism::Node` or `FreezeNodeBase` subclass - falls through to default computation using
      #   the returned node. This allows the custom generator to optionally modify the
      #   node before default processing, or simply return the original node unchanged
      #   for fallthrough.
      #
      # @param node [Prism::Node, FreezeNodeBase] Node to generate signature for
      # @return [Array, nil] Signature array
      #
      # @example Custom generator with fallthrough
      #   signature_generator = ->(node) {
      #     case node
      #     when Prism::CallNode
      #       return [:gem, node.arguments.arguments.first.unescaped] if node.name == :gem
      #     end
      #     node  # Return original node for default signature computation
      #   }
      def generate_signature(node)
        result = if @signature_generator
          custom_result = @signature_generator.call(node)
          if custom_result.is_a?(Prism::Node) || custom_result.is_a?(Ast::Merge::FreezeNodeBase)
            # Custom generator returned a node - use default computation on it
            compute_node_signature(custom_result)
          else
            # Custom result is either an array signature or nil
            custom_result
          end
        else
          compute_node_signature(node)
        end

        DebugLogger.debug("Generated signature", {
          node_type: node.class.name.split("::").last,
          signature: result,
          generator: @signature_generator ? "custom" : "default",
        }) if result

        result
      end

      # Override to detect Prism nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(::Prism::Node) || value.is_a?(Ast::Merge::FreezeNodeBase)
      end

      private

      # Safely attach comments to nodes, handling JRuby compatibility issues
      # On JRuby, the Prism::ParseResult::Comments class may not be autoloaded,
      # so we need to explicitly require it
      def attach_comments_safely!
        @parse_result.attach_comments!
      # :nocov:
      rescue NameError => e
        if e.message.include?("Comments")
          # On JRuby, the Comments class needs to be explicitly required
          require "prism/parse_result/comments"
          @parse_result.attach_comments!
        else
          raise
        end
        # :nocov:
      end

      # Extract all nodes: freeze blocks + statements outside freeze blocks
      # @return [Array<Prism::Node, FreezeNodeBase>]
      def extract_and_integrate_all_nodes
        return [] unless valid?

        body = @parse_result.value.statements
        base_statements = if body.nil?
          []
        elsif body.is_a?(Prism::StatementsNode)
          body.body.compact
        else
          [body].compact
        end

        # Extract freeze blocks by scanning comments for markers
        freeze_nodes = extract_freeze_nodes(base_statements)

        # Filter out statements inside freeze blocks
        statements_outside_freeze = filter_statements_outside_freeze(base_statements, freeze_nodes)

        # Combine and sort by line number
        all_nodes = (statements_outside_freeze + freeze_nodes).sort_by do |node|
          node.location.start_line
        end

        all_nodes
      end

      # Extract freeze blocks by scanning for freeze/unfreeze markers in comments
      # @param statements [Array<Prism::Node>] Base AST statements
      # @return [Array<FreezeNodeBase>] Freeze block nodes
      def extract_freeze_nodes(statements)
        # Skip freeze node extraction if no freeze token is configured
        return [] unless @freeze_token

        freeze_blocks = []
        freeze_start_info = nil  # { line: Integer, marker: String }
        # Use shared pattern from Ast::Merge::FreezeNodeBase with our specific token
        freeze_pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)

        # Scan all comments for freeze markers
        @parse_result.comments.each do |comment|
          line = comment.slice
          line_num = comment.location.start_line

          next unless (match = line.match(freeze_pattern))

          marker_type = match[1]&.downcase # 'freeze' or 'unfreeze'

          if marker_type == "freeze"
            if freeze_start_info
              # Nested freeze blocks not allowed
              raise FreezeNode::InvalidStructureError,
                "Nested freeze block at line #{line_num} (previous freeze at line #{freeze_start_info[:line]})"
            end
            freeze_start_info = { line: line_num, marker: line }
          elsif marker_type == "unfreeze"
            unless freeze_start_info
              raise FreezeNode::InvalidStructureError,
                "Unfreeze marker at line #{line_num} without matching freeze marker"
            end

            # Find statements enclosed by this freeze block
            enclosed_statements = statements.select do |stmt|
              stmt.location.start_line > freeze_start_info[:line] &&
                stmt.location.end_line < line_num
            end

            # Find all statements that overlap with this freeze block (for validation)
            overlapping_statements = statements.select do |stmt|
              stmt_start = stmt.location.start_line
              stmt_end = stmt.location.end_line
              # Overlaps if: starts before end AND ends after start
              stmt_start <= line_num && stmt_end >= freeze_start_info[:line]
            end

            # Create freeze node (validation happens in initialize)
            freeze_node = FreezeNode.new(
              start_line: freeze_start_info[:line],
              end_line: line_num,
              analysis: self,
              nodes: enclosed_statements,
              overlapping_nodes: overlapping_statements,
              start_marker: freeze_start_info[:marker],
              end_marker: line,
            )

            freeze_blocks << freeze_node
            freeze_start_info = nil
          end
        end

        # Handle unclosed freeze blocks
        # If freeze block is unclosed AND at root level, it extends to end of file
        # If freeze block is unclosed AND inside a nested node, it's an error
        if freeze_start_info
          # Check if any statement starts before freeze_start_info[:line] and ends after it
          # This means the freeze is inside a nested structure (class, module, method, etc.)
          nested_context = statements.any? do |stmt|
            stmt.location.start_line < freeze_start_info[:line] &&
              stmt.location.end_line > freeze_start_info[:line]
          end

          if nested_context
            raise FreezeNode::InvalidStructureError,
              "Unclosed freeze block starting at line #{freeze_start_info[:line]} inside a nested structure. " \
                "Freeze blocks inside classes/methods/modules must have matching unfreeze markers."
          end

          # Root-level unclosed freeze: extends to end of file
          last_line = @lines.length
          enclosed_statements = statements.select do |stmt|
            stmt.location.start_line > freeze_start_info[:line] &&
              stmt.location.end_line <= last_line
          end

          freeze_node = FreezeNode.new(
            start_line: freeze_start_info[:line],
            end_line: last_line,
            analysis: self,
            nodes: enclosed_statements,
            start_marker: freeze_start_info[:marker],
          )

          freeze_blocks << freeze_node
        end

        freeze_blocks
      end

      # Filter out statements that are inside freeze blocks
      # @param statements [Array<Prism::Node>] Base statements
      # @param freeze_nodes [Array<FreezeNodeBase>] Freeze block nodes
      # @return [Array<Prism::Node>] Statements outside freeze blocks
      def filter_statements_outside_freeze(statements, freeze_nodes)
        statements.reject do |stmt|
          freeze_nodes.any? do |freeze_node|
            stmt.location.start_line >= freeze_node.start_line &&
              stmt.location.end_line <= freeze_node.end_line
          end
        end
      end

      # Extract nodes with their comments and metadata.
      #
      # Uses Prism's native comment attachment via node.location. Leading comments
      # are filtered to exclude:
      # 1. Freeze/unfreeze marker comments (they belong to FreezeNodeBase boundaries)
      # 2. Comments inside freeze blocks (they belong to FreezeNodeBase content)
      #
      # This filtering prevents duplicate content when freeze blocks precede other
      # nodes, as Prism attaches ALL preceding comments to a node's leading_comments.
      #
      # @return [Array<Hash>] Array of node info hashes with keys:
      #   - :node [Prism::Node, FreezeNodeBase] The AST node
      #   - :index [Integer] Position in statements array
      #   - :leading_comments [Array<Prism::Comment>] Filtered leading comments
      #   - :inline_comments [Array<Prism::Comment>] Trailing/inline comments
      #   - :signature [Array, nil] Structural signature for matching
      #   - :line_range [Range] Line range covered by the node
      # @api private
      def extract_nodes_with_comments
        return [] unless valid?

        # Build pattern to filter out freeze/unfreeze markers from leading comments
        freeze_marker_pattern = if @freeze_token
          /#\s*#{Regexp.escape(@freeze_token)}:(freeze|unfreeze)/i
        end

        # Build a set of line numbers that are inside freeze blocks
        # Comments on these lines should not be attached as leading comments to other nodes
        freeze_block_lines = Set.new
        freeze_blocks.each do |fb|
          (fb.start_line..fb.end_line).each { |line| freeze_block_lines << line }
        end

        statements.map.with_index do |stmt, idx|
          # FreezeNodeBase doesn't have Prism location with comments
          # It's a wrapper with custom Location struct
          if stmt.is_a?(FreezeNode)
            {
              node: stmt,
              index: idx,
              leading_comments: [],
              inline_comments: [],
              signature: generate_signature(stmt),
              line_range: stmt.location.start_line..stmt.location.end_line,
            }
          else
            # Filter out comments that are:
            # 1. Freeze/unfreeze markers (part of FreezeNodeBase boundaries)
            # 2. Inside freeze blocks (belong to FreezeNodeBase content, not this node)
            leading = stmt.location.leading_comments
            if freeze_marker_pattern || freeze_block_lines.any?
              leading = leading.reject do |c|
                comment_line = c.location.start_line
                # Reject if it's a freeze marker OR if it's inside a freeze block
                (freeze_marker_pattern && c.slice.match?(freeze_marker_pattern)) ||
                  freeze_block_lines.include?(comment_line)
              end
            end

            {
              node: stmt,
              index: idx,
              leading_comments: leading,
              inline_comments: stmt.location.trailing_comments,    # Prism native!
              signature: generate_signature(stmt),
              line_range: stmt.location.start_line..stmt.location.end_line,
            }
          end
        end
      end

      # Generate default structural signature for a Prism node.
      #
      # Signatures are used to match nodes between template and destination files.
      # Nodes with identical signatures are considered "the same" for merge purposes.
      #
      # @param node [Prism::Node] Node to generate signature for
      # @return [Array] Signature array with format [:type, identifier, ...]
      #
      # @note Supported node types and their signature formats:
      #
      #   **Method/Class Definitions:**
      #   - `DefNode` → `[:def, name, [param_names]]`
      #   - `ClassNode` → `[:class, constant_path]`
      #   - `ModuleNode` → `[:module, constant_path]`
      #   - `SingletonClassNode` → `[:singleton_class, expression]`
      #
      #   **Constants:**
      #   - `ConstantWriteNode` → `[:const, name]`
      #   - `ConstantPathWriteNode` → `[:const, target]`
      #
      #   **Variable Assignments:**
      #   - `LocalVariableWriteNode` → `[:local_var, name]`
      #   - `InstanceVariableWriteNode` → `[:ivar, name]`
      #   - `ClassVariableWriteNode` → `[:cvar, name]`
      #   - `GlobalVariableWriteNode` → `[:gvar, name]`
      #   - `MultiWriteNode` → `[:multi_write, [target_names]]`
      #
      #   **Conditionals:**
      #   - `IfNode` → `[:if, condition_source]`
      #   - `UnlessNode` → `[:unless, condition_source]`
      #
      #   **Case Statements:**
      #   - `CaseNode` → `[:case, predicate]`
      #   - `CaseMatchNode` → `[:case_match, predicate]`
      #
      #   **Loops:**
      #   - `WhileNode` → `[:while, condition]`
      #   - `UntilNode` → `[:until, condition]`
      #   - `ForNode` → `[:for, index, collection]`
      #
      #   **Exception Handling:**
      #   - `BeginNode` → `[:begin, first_statement_preview]`
      #
      #   **Method Calls:**
      #   - `CallNode` (regular) → `[:call, method_name, first_arg]`
      #   - `CallNode` (assignment, e.g., `x.y = z`) → `[:call, :method=, receiver]`
      #   - `CallNode` (with block) → `[:call_with_block, method_name, first_arg_or_receiver]`
      #
      #   **Super Calls:**
      #   - `SuperNode` → `[:super, :with_block | :no_block]`
      #   - `ForwardingSuperNode` → `[:forwarding_super, :with_block | :no_block]`
      #
      #   **Lambdas:**
      #   - `LambdaNode` → `[:lambda, parameters_source]`
      #
      #   **Special Blocks:**
      #   - `PreExecutionNode` → `[:pre_execution, line_number]`
      #   - `PostExecutionNode` → `[:post_execution, line_number]`
      #
      #   **Other:**
      #   - `ParenthesesNode` → `[:parens, first_expression_preview]`
      #   - `EmbeddedStatementsNode` → `[:embedded, statements_source]`
      #   - `FreezeNodeBase` subclass → Uses FreezeNodeBase#signature
      #   - Unknown nodes → `[:other, class_name, line_number]`
      #
      # @example Method definition signature
      #   # def greet(name, greeting: "Hello")
      #   compute_node_signature(def_node)
      #   # => [:def, :greet, [:name, :greeting]]
      #
      # @example Assignment method call signature
      #   # config.setting = "value"
      #   compute_node_signature(call_node)
      #   # => [:call, :setting=, "config"]
      #
      # @example Block method call signature
      #   # appraise "ruby-3.3" do ... end
      #   compute_node_signature(call_node)
      #   # => [:call_with_block, :appraise, "ruby-3.3"]
      #
      # @api private
      def compute_node_signature(node)
        # IMPORTANT: Do NOT call node.signature - Prism nodes have their own signature method
        # that returns [node_type_symbol, source_text] which is not what we want for matching.
        # We need our own signature format: [:type_symbol, identifier, params]
        #
        # Node types with nested content (from Prism) that we may encounter:
        # - BeginNode: statements, rescue_clause, else_clause, ensure_clause
        # - BlockNode: body (handled via parent CallNode)
        # - CallNode: block
        # - CaseMatchNode: else_clause, conditions, consequent
        # - CaseNode: else_clause, conditions, consequent
        # - ClassNode: body
        # - DefNode: body
        # - ElseNode: statements (handled via parent)
        # - EmbeddedStatementsNode: statements
        # - EnsureNode: statements (handled via parent BeginNode)
        # - ForNode: statements
        # - ForwardingSuperNode: block
        # - IfNode: statements, consequent
        # - InNode: statements (handled via parent CaseMatchNode)
        # - IndexAndWriteNode, IndexOperatorWriteNode, IndexOrWriteNode: block
        # - LambdaNode: body
        # - ModuleNode: body
        # - ParenthesesNode: body
        # - PostExecutionNode: statements (END { })
        # - PreExecutionNode: statements (BEGIN { })
        # - ProgramNode: statements (top-level)
        # - RescueNode: statements, consequent (handled via parent BeginNode)
        # - SingletonClassNode: body
        # - StatementsNode: body
        # - SuperNode: block
        # - UnlessNode: statements, else_clause, consequent
        # - UntilNode: statements
        # - WhenNode: statements, conditions (handled via parent CaseNode)
        # - WhileNode: statements

        case node
        # === Method definitions ===
        when Prism::DefNode
          # Extract parameter names from ParametersNode
          params = if node.parameters
            # Handle forwarding parameters (def foo(...)) specially
            if node.parameters.is_a?(Prism::ForwardingParameterNode)
              [:forwarding]
            else
              param_names = []
              param_names.concat(node.parameters.requireds.map(&:name)) if node.parameters.requireds
              param_names.concat(node.parameters.optionals.map(&:name)) if node.parameters.optionals
              param_names << node.parameters.rest.name if node.parameters.rest&.respond_to?(:name)
              param_names.concat(node.parameters.posts.map(&:name)) if node.parameters.posts
              param_names.concat(node.parameters.keywords.map(&:name)) if node.parameters.keywords
              # keyword_rest can be KeywordRestParameterNode (has name) or ForwardingParameterNode (no name)
              if node.parameters.keyword_rest&.respond_to?(:name)
                param_names << node.parameters.keyword_rest.name
              elsif node.parameters.keyword_rest.is_a?(Prism::ForwardingParameterNode)
                param_names << :forwarding
              end
              param_names << node.parameters.block.name if node.parameters.block
              param_names
            end
          else
            []
          end
          [:def, node.name, params]

        # === Class/Module definitions ===
        when Prism::ClassNode
          [:class, node.constant_path.slice]
        when Prism::ModuleNode
          [:module, node.constant_path.slice]
        when Prism::SingletonClassNode
          # class << self or class << expr
          expr = begin
            node.expression.slice
          rescue
            "self"
          end
          [:singleton_class, expr]

        # === Constants ===
        when Prism::ConstantWriteNode
          [:const, node.name]
        when Prism::ConstantPathWriteNode
          [:const, node.target.slice]

        # === Variable assignments ===
        when Prism::LocalVariableWriteNode
          [:local_var, node.name]
        when Prism::InstanceVariableWriteNode
          [:ivar, node.name]
        when Prism::ClassVariableWriteNode
          [:cvar, node.name]
        when Prism::GlobalVariableWriteNode
          [:gvar, node.name]
        when Prism::MultiWriteNode
          # Multiple assignment: a, b = 1, 2
          targets = node.lefts.map do |target|
            case target
            when Prism::LocalVariableTargetNode
              target.name
            when Prism::InstanceVariableTargetNode
              target.name
            when Prism::ClassVariableTargetNode
              target.name
            when Prism::GlobalVariableTargetNode
              target.name
            else
              target.slice
            end
          end
          [:multi_write, targets]

        # === Conditionals ===
        when Prism::IfNode, Prism::UnlessNode
          # Conditionals match by their condition expression
          condition_source = node.predicate.slice
          [node.is_a?(Prism::IfNode) ? :if : :unless, condition_source]

        # === Case/Switch statements ===
        when Prism::CaseNode
          # case expr; when ... end - match by the expression being switched on
          predicate = node.predicate&.slice || ""
          [:case, predicate]
        when Prism::CaseMatchNode
          # case expr; in ... end (pattern matching) - match by the expression
          predicate = node.predicate&.slice || ""
          [:case_match, predicate]

        # === Loops ===
        when Prism::WhileNode
          [:while, node.predicate.slice]
        when Prism::UntilNode
          [:until, node.predicate.slice]
        when Prism::ForNode
          # for i in collection - match by index and collection
          index = node.index.slice
          collection = node.collection.slice
          [:for, index, collection]

        # === Exception handling ===
        when Prism::BeginNode
          # begin/rescue/ensure blocks - unique by position within parent
          # Since these don't have a natural identifier, use first statement
          first_stmt = node.statements&.body&.first&.slice&.[](0, 30) || ""
          [:begin, first_stmt]

        # === Method calls ===
        when Prism::CallNode
          # Method calls match by name and context
          # For assignment methods (ending in =), match by receiver + method name only
          # For other calls, include first argument as identifier (e.g., appraise "name")
          method_name = node.name.to_s
          receiver = node.receiver&.slice

          if method_name.end_with?("=")
            # Assignment method: config.setting = "value"
            # Match by receiver and method name, NOT the value being assigned
            if node.block
              [:call_with_block, node.name, receiver]
            else
              [:call, node.name, receiver]
            end
          else
            # Regular method call: appraise "unlocked" do ... end
            # Match by method name and first argument (which identifies the call)
            first_arg = extract_first_argument_value(node)
            if node.block
              [:call_with_block, node.name, first_arg]
            else
              [:call, node.name, first_arg]
            end
          end

        # === Super calls ===
        when Prism::SuperNode
          [:super, node.block ? :with_block : :no_block]
        when Prism::ForwardingSuperNode
          [:forwarding_super, node.block ? :with_block : :no_block]

        # === Lambdas ===
        when Prism::LambdaNode
          # Lambdas don't have names, but we can identify by parameter signature
          params = if node.parameters
            node.parameters.slice
          else
            ""
          end
          [:lambda, params]

        # === Special blocks ===
        when Prism::PreExecutionNode
          # BEGIN { } blocks
          [:pre_execution, node.location.start_line]
        when Prism::PostExecutionNode
          # END { } blocks
          [:post_execution, node.location.start_line]

        # === Parenthesized expressions ===
        when Prism::ParenthesesNode
          # Usually transparent, but if it appears at top level, identify by content
          first_expr = node.body&.body&.first&.slice&.[](0, 30) || ""
          [:parens, first_expr]

        # === Embedded statements (string interpolation) ===
        when Prism::EmbeddedStatementsNode
          [:embedded, node.statements&.slice || ""]

        # === FreezeNodeBase subclass (our custom wrapper) ===
        when FreezeNode
          # FreezeNodeBase has its own signature method with normalized content
          node.signature

        else
          # Fallback: use class name and line number
          # Nodes that reach here may not merge well across files
          [:other, node.class.name, node.location.start_line]
        end
      end

      # Extract the value of the first argument from a CallNode for signature matching.
      # Returns the unescaped string value for StringNode, or the slice for other node types.
      #
      # @param node [Prism::CallNode] The call node to extract argument from
      # @return [String, nil] The first argument value, or nil if no arguments
      def extract_first_argument_value(node)
        return unless node.arguments&.arguments&.any?

        first_arg = node.arguments.arguments.first
        case first_arg
        when Prism::StringNode
          first_arg.unescaped
        when Prism::SymbolNode
          first_arg.unescaped.to_sym
        else
          first_arg.slice
        end
      end
    end
  end
end
