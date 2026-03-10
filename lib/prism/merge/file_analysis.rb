# frozen_string_literal: true

require "ast/merge/comment"
require_relative "comment"

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

      class NativeCommentAugmenter
        attr_reader :capability, :attachments_by_owner, :preamble_region, :postlude_region, :orphan_regions

        def initialize(analysis, owners: [], **details)
          @analysis = analysis
          @owners = Array(owners)
          @capability = Ast::Merge::Comment::Capability.native_full(
            source: :prism,
            style: :hash_comment,
            attachment_hints: true,
            comment_nodes: true,
            owner_count: @owners.size,
            comment_count: @analysis.comment_nodes.size,
            **details,
          )
          @attachments_by_owner = {}
          @preamble_region = nil
          @postlude_region = nil
          @orphan_regions = []
          build!
        end

        def attachment_for(owner)
          @attachments_by_owner[owner]
        end

        private

        def build!
          if @analysis.send(:comment_only_file?)
            entries = @analysis.send(:native_comment_entries_in_range, 1..@analysis.lines.length).select { |entry| entry[:full_line] }
            @preamble_region = @analysis.send(:build_comment_region, :preamble, entries) if entries.any?
            return
          end

          @owners.each do |owner|
            @attachments_by_owner[owner] = @analysis.comment_attachment_for(owner)
          end

          if @owners.empty?
            @preamble_region = @analysis.comment_region_for_range(1..@analysis.lines.length, kind: :preamble, full_line_only: true)
            return
          end

          first_owner_start = @analysis.send(:owner_start_line, @owners.first)
          last_owner_end = @analysis.send(:owner_end_line, @owners.last)

          if first_owner_start && first_owner_start > 1
            preamble_entries = @analysis.send(:native_comment_entries_in_range, 1..(first_owner_start - 1)).select { |entry| entry[:full_line] }
            @preamble_region = @analysis.send(:build_comment_region, :preamble, preamble_entries) if preamble_entries.any?
          end

          if last_owner_end && last_owner_end < @analysis.lines.length
            postlude_entries = @analysis.send(:native_comment_entries_in_range, (last_owner_end + 1)..@analysis.lines.length).select { |entry| entry[:full_line] }
            @postlude_region = @analysis.send(:build_comment_region, :postlude, postlude_entries) if postlude_entries.any?
          end
        end
      end

      # Default freeze token for identifying freeze blocks
      DEFAULT_FREEZE_TOKEN = "prism-merge"

      # @return [Prism::ParseResult] The parse result from Prism
      attr_reader :parse_result

      # Initialize file analysis with Prism's native comment handling
      #
      # @param source [String] Ruby source code to analyze
      # @param freeze_token [String] Token for freeze block markers (default: "prism-merge")
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param options [Hash] Additional options for forward compatibility
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, **options)
        @source = source
        @lines = source.lines
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        # **options captured for forward compatibility
        @parse_result = DebugLogger.time("FileAnalysis#parse") { Prism.parse(source) }

        # Use Prism's native comment attachment
        # On JRuby, the Comments class may not be loaded yet, so we need to require it
        attach_comments_safely!

        # Extract and validate structure
        @statements = extract_and_integrate_all_nodes

        DebugLogger.debug("FileAnalysis initialized", {
          signature_generator: signature_generator ? "custom" : "default",
          statements_count: @statements.size,
          frozen_nodes_count: frozen_nodes.size,
        })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @parse_result.success?
      end

      # Get parse errors for compatibility with SmartMergerBase.
      # @return [Array<Prism::ParseError>] Array of parse errors
      def errors
        @parse_result.errors
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Ast::Merge::Comment::Capability]
      def comment_capability
        @comment_capability ||= Ast::Merge::Comment::Capability.native_full(
          source: :prism,
          style: :hash_comment,
          attachment_hints: true,
          comment_nodes: true,
          comment_count: comment_nodes.size,
        )
      end

      # Get all supported comments converted to shared/native Ruby comment nodes.
      #
      # @return [Array<Prism::Merge::Comment::Line>]
      def comment_nodes
        native_comment_entries.map { |entry| entry[:node] }
      end

      # Get a shared/native Ruby comment node at a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Prism::Merge::Comment::Line, nil]
      def comment_node_at(line_num)
        native_comment_entries.find { |entry| entry[:line] == line_num }&.dig(:node)
      end

      # Get comments in a line range converted to a shared comment region.
      #
      # @param range [Range] Range of 1-based line numbers
      # @param kind [Symbol] Region kind (:leading, :inline, :orphan, etc.)
      # @param full_line_only [Boolean] Whether to keep only full-line comments
      # @return [Ast::Merge::Comment::Region]
      def comment_region_for_range(range, kind:, full_line_only: false)
        entries = native_comment_entries_in_range(range)
        entries = entries.select { |entry| entry[:full_line] } if full_line_only
        build_comment_region(kind, entries, metadata: {range: range, full_line_only: full_line_only})
      end

      # Build a native shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata preserved on the attachment
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment_for(owner, **options)
        leading_region = build_comment_region(:leading, owner_leading_comment_entries(owner))
        inline_region = build_comment_region(:inline, owner_inline_comment_entries(owner))

        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: leading_region,
          inline_region: inline_region,
          metadata: {
            source: :prism_native,
            line_num: owner_start_line(owner),
          }.merge(options),
        )
      end

      # Build a native shared comment augmenter for this analysis.
      #
      # @param owners [Array<#start_line,#end_line>, nil] Owners used for attachment exposure
      # @param options [Hash] Additional capability details
      # @return [NativeCommentAugmenter]
      def comment_augmenter(owners: nil, **options)
        NativeCommentAugmenter.new(self, owners: owners || comment_augmenter_default_owners, **options)
      end

      # Get nodes with their associated comments and metadata
      # Comments are now accessed via Prism's native node.location API
      # @return [Array<Hash>] Array of node info hashes
      def nodes_with_comments
        @nodes_with_comments ||= extract_nodes_with_comments
      end

      # Override to detect Prism nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(::Prism::Node) || super
      end

      # Determine if a node is frozen (has a freeze marker in its leading comments).
      #
      # For Ruby AST nodes, a freeze marker applies only to the node it directly
      # precedes in leading comments. If a freeze marker appears INSIDE a block
      # (nested in the body), it applies to that nested statement, NOT the outer
      # block. This is different from comment-only formats like Markdown where
      # checking content containment makes sense.
      #
      # Nested freeze markers inside the node's body are handled during recursive
      # body merging, where each nested statement gets its own freeze detection.
      #
      # @param node [Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper] The node to check
      # @return [Boolean] true if the node has a freeze marker in its leading comments
      def frozen_node?(node)
        # Already wrapped as frozen
        return true if node.is_a?(Ast::Merge::Freezable)

        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # Check for freeze marker in leading comments ONLY
        if actual_node.respond_to?(:location) && actual_node.location.respond_to?(:leading_comments)
          return true if actual_node.location.leading_comments.any? { |c| c.slice.match?(freeze_pattern) }
        end

        false
      end

      # Get nodes that are frozen (have a freeze marker).
      # Returns FrozenWrapper instances that include the Freezable behavior,
      # allowing them to satisfy both is_a?(Freezable) and is_a?(NodeTyping::Wrapper).
      #
      # @return [Array<Ast::Merge::NodeTyping::FrozenWrapper>] Wrapped frozen nodes
      def frozen_nodes
        # Return the underlying Prism nodes for tests and callers that expect
        # Prism node types. Statements may be wrapped in FrozenWrapper; unwrap
        # them here.
        statements.select { |node| node.is_a?(Ast::Merge::Freezable) }
          .map { |node| node.respond_to?(:unwrap) ? node.unwrap : node }
      end

      class << self
        # Safely attach comments to nodes, handling JRuby compatibility issues.
        # On JRuby, the Prism::ParseResult::Comments class may not be autoloaded,
        # so we need to explicitly require it.
        #
        # This is a class method so it can be used anywhere in prism-merge code
        # that needs to attach comments to a parse result.
        #
        # @param parse_result [Prism::ParseResult] The parse result to attach comments to
        # @return [void]
        def attach_comments_safely!(parse_result)
          parse_result.attach_comments!
        # :nocov: defensive - JRuby compatibility for Comments class autoloading
        rescue NameError => e
          if e.message.include?("Comments")
            # On JRuby, the Comments class needs to be explicitly required
            require "prism/parse_result/comments"
            parse_result.attach_comments!
          else
            raise
          end
          # :nocov:
        end
      end

      private

      def comment_augmenter_default_owners
        @comment_augmenter_default_owners ||= statements.select do |stmt|
          owner_start_line(stmt) && owner_end_line(stmt)
        end
      end

      def native_comment_entries
        @native_comment_entries ||= begin
          if comment_only_file?
            comment_entries_from_comment_only_statements
          else
            unique_comment_entries(comment_entries_from_attached_nodes)
          end
        end
      end

      def native_comment_entries_in_range(range)
        native_comment_entries.select { |entry| range.cover?(entry[:line]) }
      end

      def build_comment_region(kind, entries, metadata: {})
        return if entries.empty?

        Ast::Merge::Comment::Region.new(
          kind: kind,
          nodes: entries.map { |entry| entry[:node] },
          metadata: {
            source: :prism_native,
            entries: entries,
          }.merge(metadata),
        )
      end

      def owner_start_line(owner)
        if owner.respond_to?(:location) && owner.location
          owner.location.start_line
        elsif owner.respond_to?(:start_line)
          owner.start_line
        elsif owner.respond_to?(:line_number)
          owner.line_number
        end
      end

      def owner_end_line(owner)
        if owner.respond_to?(:location) && owner.location
          owner.location.end_line
        elsif owner.respond_to?(:end_line)
          owner.end_line
        elsif owner.respond_to?(:line_number)
          owner.line_number
        end
      end

      def owner_leading_comment_entries(owner)
        native_comments_for(owner, :leading_comments).map do |comment|
          native_comment_entry(comment, attached_as: :leading)
        end
      end

      def owner_inline_comment_entries(owner)
        owner_last_line = owner_end_line(owner)
        native_comments_for(owner, :trailing_comments).filter_map do |comment|
          entry = native_comment_entry(comment, attached_as: :trailing)
          entry unless entry[:full_line] || (owner_last_line && entry[:line] > owner_last_line)
        end
      end

      def native_comments_for(owner, kind)
        return [] unless owner.respond_to?(:location) && owner.location.respond_to?(kind)

        Array(owner.location.public_send(kind))
      end

      def comment_entries_from_attached_nodes
        nodes_with_comments.flat_map do |node_info|
          Array(node_info[:leading_comments]).map { |comment| native_comment_entry(comment, attached_as: :leading) } +
            Array(node_info[:inline_comments]).map { |comment| native_comment_entry(comment, attached_as: :trailing) }
        end
      end

      def comment_entries_from_comment_only_statements
        statements.filter_map do |stmt|
          case stmt
          when Prism::Merge::Comment::Block
            stmt.children.filter_map { |child| comment_entry_from_comment_ast_node(child) }
          when Prism::Merge::Comment::Line
            comment_entry_from_comment_ast_node(stmt)
          end
        end.flatten
      end

      def comment_entry_from_comment_ast_node(node)
        return unless node.is_a?(Prism::Merge::Comment::Line)

        {
          line: node.line_number,
          text: node.content,
          raw: node.text,
          full_line: true,
          attached_as: :comment_only,
          node: node,
        }
      end

      def native_comment_entry(comment, attached_as:)
        line = comment.location.start_line
        {
          line: line,
          text: comment_content(comment),
          raw: comment.slice.chomp,
          full_line: full_line_comment?(comment, attached_as: attached_as),
          attached_as: attached_as,
          node: Prism::Merge::Comment::Line.new(text: comment.slice.chomp, line_number: line),
        }
      end

      def full_line_comment?(comment, attached_as:)
        return true if attached_as == :leading

        line = @lines[comment.location.start_line - 1].to_s
        line.lstrip.start_with?("#")
      end

      def comment_content(comment)
        comment.slice.sub(/\A\s*#\s?/, "")
      end

      def unique_comment_entries(entries)
        entries.uniq do |entry|
          [entry[:line], entry[:raw], entry[:attached_as]]
        end.sort_by { |entry| [entry[:line], entry[:attached_as] == :trailing ? 1 : 0] }
      end

      def comment_only_file?
        statements.any? && statements.all? { |stmt| stmt.is_a?(Ast::Merge::AstNode) }
      end

      # Instance method wrapper for class method
      def attach_comments_safely!
        self.class.attach_comments_safely!(@parse_result)
      end

      # Extract all top-level AST nodes from the parsed source.
      #
      # Freeze semantics are simplified: a node is frozen if it has a freeze marker
      # (`# token:freeze`) in its leading comments or content. Closing markers
      # (`# token:unfreeze`) have no effect - they can exist but are ignored.
      #
      # Frozen nodes are wrapped in FrozenWrapper to satisfy the Freezable API,
      # enabling them to be detected via is_a?(Freezable) and freeze_node?.
      #
      # Use `frozen_node?` to check if a specific node is frozen.
      #
      # @return [Array<Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper>] Top-level statements
      def extract_and_integrate_all_nodes
        return [] unless valid?

        body = @parse_result.value.statements
        raw_nodes = if body.nil?
          # :nocov: defensive - Prism currently always returns StatementsNode
          []
          # :nocov:
        elsif body.is_a?(Prism::StatementsNode)
          body.body.compact
        else
          # :nocov: defensive - hypothetical case where body is a single node
          [body].compact
          # :nocov:
        end

        # If no Prism statements but we have content, build comment AST
        # This handles files with only comments (e.g., # frozen_string_literal: true)
        if raw_nodes.empty? && @lines.any?
          return Comment::Parser.parse(@lines)
        end

        # Wrap frozen nodes in FrozenWrapper to satisfy Freezable API
        raw_nodes.map do |node|
          if frozen_node?(node)
            Ast::Merge::NodeTyping::FrozenWrapper.new(node, :frozen)
          else
            node
          end
        end
      end

      # Extract nodes with their comments and metadata.
      #
      # Uses Prism's native comment attachment via node.location.
      #
      # @return [Array<Hash>] Array of node info hashes with keys:
      #   - :node [Prism::Node] The AST node
      #   - :index [Integer] Position in statements array
      #   - :leading_comments [Array<Prism::Comment>] Leading comments
      #   - :inline_comments [Array<Prism::Comment>] Trailing/inline comments
      #   - :signature [Array, nil] Structural signature for matching
      #   - :line_range [Range] Line range covered by the node
      # @api private
      def extract_nodes_with_comments
        return [] unless valid?

        statements.map.with_index do |stmt, idx|
          # Handle custom AST nodes (CommentBlock, CommentLine, EmptyLine)
          if stmt.is_a?(Ast::Merge::AstNode)
            {
              node: stmt,
              index: idx,
              leading_comments: [],
              inline_comments: [],
              signature: stmt.signature,
              line_range: stmt.location.start_line..stmt.location.end_line,
            }
          else
            # Unwrap any FrozenWrapper to provide the underlying Prism node as
            # the primary :node value while still using the wrapper for comment
            # attachment (delegation via method_missing preserves location access).
            actual_node = stmt.respond_to?(:unwrap) ? stmt.unwrap : stmt

            {
              node: actual_node,
              index: idx,
              leading_comments: (stmt.location.respond_to?(:leading_comments) ? stmt.location.leading_comments : []),
              inline_comments: (stmt.location.respond_to?(:trailing_comments) ? stmt.location.trailing_comments : []),
              signature: generate_signature(actual_node),
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
        # Handle our custom AST nodes (CommentBlock, CommentLine, EmptyLine, etc.)
        # These have their own signature method that returns the appropriate format
        if node.is_a?(Ast::Merge::AstNode)
          return node.signature
        end

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
              # :nocov: defensive - current Prism wraps ForwardingParameterNode in ParametersNode
              [:forwarding]
              # :nocov:
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
              # :nocov: defensive - Ruby syntax doesn't allow blocks with assignment methods
              [:call_with_block, node.name, receiver]
              # :nocov:
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
