# frozen_string_literal: true

module Prism
  module Merge
    # Orchestrates the smart merge process using FileAnalysis, FileAligner,
    # ConflictResolver, and MergeResult to merge two Ruby files intelligently.
    #
    # SmartMerger provides flexible configuration for different merge scenarios.
    # When matching class or module definitions are found in both files, the merger
    # automatically performs recursive merging of their bodies, intelligently combining
    # nested methods, constants, and other definitions.
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Version file merge (template updates win)
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_match_preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #   # Result: VERSION = "2.0.0" (from template), new constants added
    #
    # @example Appraisals merge (destination customizations preserved)
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_match_preference: :destination,  # default
    #     add_template_only_nodes: false             # default
    #   )
    #   result = merger.merge
    #   # Result: Custom gem versions preserved, template-only blocks skipped
    #
    # @example Custom signature matching
    #   sig_gen = ->(node) { [node.class.name, node.name] }
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_generator: sig_gen
    #   )
    #
    # @see FileAnalysis
    # @see FileAligner
    # @see ConflictResolver
    # @see MergeResult
    class SmartMerger
      # @return [FileAnalysis] Analysis of the template file
      attr_reader :template_analysis

      # @return [FileAnalysis] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [FileAligner] Aligner for finding matches and differences
      attr_reader :aligner

      # @return [ConflictResolver] Resolver for handling conflicting content
      attr_reader :resolver

      # @return [MergeResult] Result object tracking merged content
      attr_reader :result

      # Creates a new SmartMerger for intelligent Ruby file merging.
      #
      # @param template_content [String] Template Ruby source code
      # @param dest_content [String] Destination Ruby source code
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom node signatures.
      #   The proc receives a Prism node (or FreezeNode) and should return one of:
      #   - An array representing the node's signature (e.g., `[:gem, "foo"]`)
      #   - `nil` to indicate the node should have no signature (won't be matched)
      #   - A `Prism::Node` or `FreezeNode` to fall through to default signature computation
      #     using that node. This allows custom generators to only override specific node
      #     types while delegating others to the built-in logic. Return the original node
      #     unchanged for simple fallthrough, or return a modified node to influence
      #     default matching.
      #
      #   Nodes with identical signatures are considered matches during merge.
      #   Default: Uses {FileAnalysis#compute_node_signature} which matches:
      #   - Conditionals by condition only (not body)
      #   - Assignments by name only (not value)
      #   - Method calls by name and args (not block)
      #
      # @param signature_match_preference [Symbol] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations).
      #     Use for Appraisals files, configs with project-specific values.
      #   - `:template` - Use template version (applies updates).
      #     Use for version files, canonical configs, conditional implementations.
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes.
      #     Use for templates with placeholder/example content.
      #   - `true` - Add template-only nodes to result.
      #     Use when template has new required constants/methods to add.
      #
      # @param freeze_token [String] Token to use for freeze block markers.
      #   Default: "prism-merge" (looks for # prism-merge:freeze / # prism-merge:unfreeze)
      #   Freeze blocks preserve destination content unchanged during merge.
      #
      # @param max_recursion_depth [Integer, Float] Maximum depth for recursive body merging.
      #   Default: Float::INFINITY (no limit). This is a safety valve that users can set
      #   if they encounter edge cases. Normal merging terminates naturally based on
      #   body content analysis (blocks with non-mergeable content like literals are
      #   not recursed into).
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      #
      # @example Basic usage
      #   merger = SmartMerger.new(template, destination)
      #   result = merger.merge
      #
      # @example Template updates win (version files)
      #   merger = SmartMerger.new(
      #     template,
      #     destination,
      #     signature_match_preference: :template,
      #     add_template_only_nodes: true
      #   )
      #
      # @example Destination customizations win (Appraisals)
      #   merger = SmartMerger.new(
      #     template,
      #     destination,
      #     signature_match_preference: :destination,
      #     add_template_only_nodes: false
      #   )
      #
      # @example Custom signature matching with fallthrough
      #   sig_gen = lambda do |node|
      #     case node
      #     when Prism::CallNode
      #       # Custom handling for gem calls - match by gem name
      #       if node.name == :gem
      #         return [:gem, node.arguments&.arguments&.first&.unescaped]
      #       end
      #     end
      #     # Return the node to fall through to default signature computation
      #     node
      #   end
      #
      #   merger = SmartMerger.new(
      #     template,
      #     destination,
      #     signature_generator: sig_gen
      #   )
      def initialize(template_content, dest_content, signature_generator: nil, signature_match_preference: :destination, add_template_only_nodes: false, freeze_token: FileAnalysis::DEFAULT_FREEZE_TOKEN, max_recursion_depth: Float::INFINITY, current_depth: 0)
        @template_content = template_content
        @dest_content = dest_content
        @signature_match_preference = signature_match_preference
        @add_template_only_nodes = add_template_only_nodes
        @freeze_token = freeze_token
        @max_recursion_depth = max_recursion_depth
        @current_depth = current_depth
        @template_analysis = FileAnalysis.new(template_content, signature_generator: signature_generator, freeze_token: freeze_token)
        @dest_analysis = FileAnalysis.new(dest_content, signature_generator: signature_generator, freeze_token: freeze_token)
        @aligner = FileAligner.new(@template_analysis, @dest_analysis)
        @resolver = ConflictResolver.new(
          @template_analysis,
          @dest_analysis,
          signature_match_preference: signature_match_preference,
          add_template_only_nodes: add_template_only_nodes,
        )
        @result = MergeResult.new
      end

      # Performs the intelligent merge of template and destination files.
      #
      # The merge process:
      # 1. Validates both files for syntax errors
      # 2. Finds anchors (matching sections) and boundaries (differences)
      # 3. Processes anchors and boundaries in order
      # 4. Returns merged content as a string
      #
      # Merge behavior is controlled by constructor parameters:
      # - `signature_match_preference`: Which version wins for matching nodes
      # - `add_template_only_nodes`: Whether to add template-only content
      #
      # @return [String] The merged Ruby source code
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      #
      # @example Basic merge
      #   merger = SmartMerger.new(template, destination)
      #   result = merger.merge
      #   File.write("output.rb", result)
      #
      # @example With error handling
      #   begin
      #     result = merger.merge
      #   rescue Prism::Merge::TemplateParseError => e
      #     puts "Template error: #{e.message}"
      #     puts "Parse errors: #{e.parse_result.errors}"
      #   end
      #
      # @see #merge_with_debug for detailed merge information
      def merge
        # Handle invalid files
        unless @template_analysis.valid?
          raise Prism::Merge::TemplateParseError.new(
            "Template file has parsing errors",
            content: @template_content,
            parse_result: @template_analysis.parse_result,
          )
        end

        unless @dest_analysis.valid?
          raise Prism::Merge::DestinationParseError.new(
            "Destination file has parsing errors",
            content: @dest_content,
            parse_result: @dest_analysis.parse_result,
          )
        end

        # Find anchors and boundaries
        boundaries = @aligner.align

        # Process the merge by walking through anchors and boundaries in order
        process_merge(boundaries)

        # Return final content
        @result.to_s
      end

      # Performs merge and returns detailed debug information.
      #
      # This method provides comprehensive information about merge decisions,
      # useful for debugging, testing, and understanding merge behavior.
      #
      # @return [Hash] Hash containing:
      #   - `:content` [String] - Final merged content
      #   - `:debug` [String] - Line-by-line provenance information
      #   - `:statistics` [Hash] - Counts of merge decisions:
      #     - `:kept_template` - Lines from template (no conflict)
      #     - `:kept_destination` - Lines from destination (no conflict)
      #     - `:replaced` - Template replaced matching destination
      #     - `:appended` - Destination-only content added
      #     - `:freeze_block` - Lines from freeze blocks
      #
      # @example Get merge statistics
      #   result = merger.merge_with_debug
      #   puts "Template lines: #{result[:statistics][:kept_template]}"
      #   puts "Replaced lines: #{result[:statistics][:replaced]}"
      #
      # @example Debug line provenance
      #   result = merger.merge_with_debug
      #   puts result[:debug]
      #   # Output shows source file and decision for each line:
      #   # Line 1: [KEPT_TEMPLATE] # frozen_string_literal: true
      #   # Line 2: [KEPT_TEMPLATE]
      #   # Line 3: [REPLACED] VERSION = "2.0.0"
      #
      # @see #merge for basic merge without debug info
      def merge_with_debug
        content = merge
        {
          content: content,
          debug: @result.debug_output,
          statistics: @result.statistics,
        }
      end

      private

      def process_merge(boundaries)
        # Build complete timeline of anchors and boundaries
        timeline = build_timeline(boundaries)

        timeline.each do |item|
          if item[:type] == :anchor
            process_anchor(item[:anchor])
          else
            process_boundary(item[:boundary])
          end
        end
      end

      def build_timeline(boundaries)
        timeline = []

        # Add all anchors and boundaries sorted by position
        @aligner.anchors.each do |anchor|
          timeline << {type: :anchor, anchor: anchor, sort_key: [anchor.template_start, 0]}
        end

        boundaries.each do |boundary|
          # Sort boundaries by their position relative to anchors
          # - Boundaries before first anchor: use their position (or 0 if no template range)
          # - Boundaries between anchors: use template position
          # - Boundaries after last anchor: use Float::INFINITY to place at end

          if boundary.prev_anchor.nil? && boundary.next_anchor
            # Before first anchor - place at beginning
            t_start = boundary.template_range&.begin || 0
            d_start = boundary.dest_range&.begin || 0
          elsif boundary.prev_anchor && boundary.next_anchor.nil?
            # After last anchor - place at end
            t_start = Float::INFINITY
            d_start = boundary.dest_range&.begin || Float::INFINITY
          else
            # Between anchors or no anchors at all
            t_start = boundary.template_range&.begin || boundary.prev_anchor&.template_end&.+(1) || 0
            d_start = boundary.dest_range&.begin || 0
          end

          sort_key = [t_start, d_start, 1] # 1 ensures boundaries come after anchors at same position

          timeline << {type: :boundary, boundary: boundary, sort_key: sort_key}
        end

        timeline.sort_by! { |item| item[:sort_key] }
        timeline
      end

      def process_anchor(anchor)
        # Anchors represent identical or equivalent sections - just copy them
        case anchor.match_type
        when :freeze_block
          # Freeze blocks from destination take precedence
          add_freeze_block_from_dest(anchor)
        when :signature_match
          # For signature matches (same structure, different content), prefer destination
          add_signature_match_from_dest(anchor)
        when :exact_match
          # For exact matches, prefer template (it's the source of truth)
          add_exact_match_from_template(anchor)
        else
          # Unknown match type - default to template
          add_exact_match_from_template(anchor)
        end
      end

      def add_freeze_block_from_dest(anchor)
        anchor.dest_range.each do |line_num|
          line = @dest_analysis.line_at(line_num)
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_FREEZE_BLOCK,
            dest_line: line_num,
          )
        end
      end

      def add_signature_match_from_dest(anchor)
        # Find the nodes corresponding to this anchor
        # Look for nodes that overlap with the anchor range (not just at start line)
        template_node = find_node_in_range(@template_analysis, anchor.template_start, anchor.template_end)
        dest_node = find_node_in_range(@dest_analysis, anchor.dest_start, anchor.dest_end)

        # Check if this is a class or module that should be recursively merged
        if should_merge_recursively?(template_node, dest_node)
          merge_node_body_recursively(template_node, dest_node, anchor)
        elsif @signature_match_preference == :template
          # Use template version (for updates/canonical values)
          anchor.template_range.each do |line_num|
            line = @template_analysis.line_at(line_num)
            @result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_REPLACED,
              template_line: line_num,
            )
          end
        else
          # Use destination version (for customizations)
          anchor.dest_range.each do |line_num|
            line = @dest_analysis.line_at(line_num)
            @result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_REPLACED,
              dest_line: line_num,
            )
          end
        end
      end

      def add_exact_match_from_template(anchor)
        anchor.template_range.each do |line_num|
          line = @template_analysis.line_at(line_num)
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_KEPT_TEMPLATE,
            template_line: line_num,
          )
        end
      end

      def process_boundary(boundary)
        @resolver.resolve(boundary, @result)
      end

      # Find a node that overlaps with the given line range.
      # This handles cases where anchors include leading comments (e.g., magic comments).
      #
      # @param analysis [FileAnalysis] The file analysis to search
      # @param start_line [Integer] Start line of the range
      # @param end_line [Integer] End line of the range
      # @return [Prism::Node, nil] The first node that overlaps with the range, or nil if none found
      def find_node_in_range(analysis, start_line, end_line)
        # Find a node that overlaps with the range
        analysis.statements.find do |stmt|
          # Check if node overlaps with the range
          stmt.location.start_line <= end_line && stmt.location.end_line >= start_line
        end
      end

      # Find the node at a specific line in the analysis (deprecated - use find_node_in_range)
      # @deprecated Use {#find_node_in_range} instead for better handling of leading comments
      # @param analysis [FileAnalysis] The file analysis to search
      # @param line_num [Integer] The line number to find a node at
      # @return [Prism::Node, nil] The node at that line, or nil if none found
      def find_node_at_line(analysis, line_num)
        analysis.statements.find do |stmt|
          line_num.between?(stmt.location.start_line, stmt.location.end_line)
        end
      end

      # Determines if two matching nodes should be recursively merged.
      #
      # Recursive merge is performed for matching class/module definitions and
      # CallNodes with blocks to intelligently combine their body contents
      # (nested methods, constants, etc.). This allows template updates to
      # internals to be merged with destination customizations.
      #
      # @param template_node [Prism::Node, nil] Node from template file
      # @param dest_node [Prism::Node, nil] Node from destination file
      # @return [Boolean] true if nodes should be recursively merged
      #
      # @note Recursive merge is NOT performed for:
      #   - Conditional nodes (if/unless) - treated as atomic units
      #   - Classes/modules/blocks containing freeze blocks - frozen content would be lost
      #   - Nodes of different types
      #   - Blocks whose body contains only literals/expressions with no mergeable statements
      #   - When max_recursion_depth has been reached (safety valve)
      def should_merge_recursively?(template_node, dest_node)
        return false unless template_node && dest_node

        # Safety valve: stop recursion if max depth reached
        return false if @current_depth >= @max_recursion_depth

        # Both nodes must be the same type
        return false unless template_node.class == dest_node.class

        # Determine if this node type supports recursive merging
        can_merge_recursively = case template_node
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          # Class/module definitions - merge their body contents
          true
        when Prism::CallNode
          # Only merge if both have blocks with mergeable content
          template_node.block && dest_node.block &&
            body_has_mergeable_statements?(template_node.block.body) &&
            body_has_mergeable_statements?(dest_node.block.body)
        when Prism::BeginNode
          # begin/rescue/ensure blocks - merge statements
          template_node.statements && dest_node.statements
        when Prism::CaseNode, Prism::CaseMatchNode
          # Case statements could potentially merge conditions, but this is complex
          # For now, treat as atomic unless both have same structure
          false
        when Prism::WhileNode, Prism::UntilNode, Prism::ForNode
          # Loops - could merge body, but usually should be atomic
          false
        when Prism::LambdaNode
          # Lambdas - could merge body, but typically atomic
          false
        else
          false
        end

        return false unless can_merge_recursively

        true
      end

      # Check if a body (StatementsNode) contains statements that could be merged.
      #
      # Mergeable statements are those that can generate signatures and be
      # independently matched between template and destination. This includes
      # method definitions, class/module definitions, method calls, assignments, etc.
      #
      # Bodies containing only literals (strings, numbers, arrays, hashes) or
      # simple expressions should not be recursively merged as there's nothing
      # to align - they should be treated atomically.
      #
      # @param body [Prism::StatementsNode, nil] The body to check
      # @return [Boolean] true if the body contains mergeable statements
      # @api private
      def body_has_mergeable_statements?(body)
        return false unless body.is_a?(Prism::StatementsNode)
        return false if body.body.empty?

        body.body.any? { |stmt| mergeable_statement?(stmt) }
      end

      # Check if a statement is mergeable (can generate a signature).
      #
      # @param node [Prism::Node] The node to check
      # @return [Boolean] true if this node type can be merged
      # @api private
      def mergeable_statement?(node)
        case node
        when Prism::CallNode, Prism::DefNode, Prism::ClassNode, Prism::ModuleNode,
             Prism::SingletonClassNode, Prism::ConstantWriteNode, Prism::ConstantPathWriteNode,
             Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode,
             Prism::ClassVariableWriteNode, Prism::GlobalVariableWriteNode,
             Prism::MultiWriteNode, Prism::IfNode, Prism::UnlessNode, Prism::CaseNode,
             Prism::BeginNode
          true
        else
          false
        end
      end

      # Check if a node's body contains freeze block markers.
      #
      # @param node [Prism::Node] The node to check
      # @param analysis [FileAnalysis] The analysis for the file containing this node
      # @return [Boolean] true if the node's body contains freeze block comments
      # @api private
      def node_contains_freeze_blocks?(node, analysis)
        return false unless @freeze_token

        # Check if node has nested content that could contain freeze blocks
        # Different node types store content in different attributes
        has_content = case node
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode,
             Prism::LambdaNode, Prism::ParenthesesNode
          node.body
        when Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode,
             Prism::ForNode, Prism::BeginNode
          node.statements
        when Prism::CallNode, Prism::SuperNode, Prism::ForwardingSuperNode
          node.block
        else
          # Fallback for any other nodes
          node.respond_to?(:body) && node.body ||
            node.respond_to?(:statements) && node.statements ||
            node.respond_to?(:block) && node.block
        end

        return false unless has_content

        # Check if any comments in the node's range contain freeze markers
        # Only check comments from the analysis that owns this node
        freeze_pattern = /#\s*#{Regexp.escape(@freeze_token)}:(freeze|unfreeze)/i

        node_start = node.location.start_line
        node_end = node.location.end_line

        analysis.parse_result.comments.any? do |comment|
          comment_line = comment.location.start_line
          comment_line > node_start && comment_line < node_end && comment.slice.match?(freeze_pattern)
        end
      end

      # Recursively merges the body of matching class, module, or call-with-block nodes.
      #
      # This method extracts the body content (everything between the opening
      # declaration and the closing 'end'), creates a new nested SmartMerger to merge
      # those bodies, and then reassembles the complete node with the merged body.
      #
      # @param template_node [Prism::ClassNode, Prism::ModuleNode, Prism::CallNode] Node from template
      # @param dest_node [Prism::ClassNode, Prism::ModuleNode, Prism::CallNode] Node from destination
      # @param anchor [FileAligner::Anchor] The anchor representing this match
      #
      # @note The nested merger is configured with:
      #   - Same signature_generator, signature_match_preference, add_template_only_nodes, and freeze_token
      #   - Incremented current_depth to track recursion level
      #
      # @api private
      def merge_node_body_recursively(template_node, dest_node, anchor)
        # Extract the body source for both nodes
        template_body = extract_node_body(template_node, @template_analysis)
        dest_body = extract_node_body(dest_node, @dest_analysis)

        # Recursively merge the bodies with incremented depth
        # Pass freeze_token so freeze blocks inside nested bodies are preserved
        body_merger = SmartMerger.new(
          template_body,
          dest_body,
          signature_generator: @template_analysis.instance_variable_get(:@signature_generator),
          signature_match_preference: @signature_match_preference,
          add_template_only_nodes: @add_template_only_nodes,
          freeze_token: @freeze_token,
          max_recursion_depth: @max_recursion_depth,
          current_depth: @current_depth + 1,
        )
        merged_body = body_merger.merge.rstrip

        # Determine leading comments handling:
        # - If template has leading comments, use template's based on signature_match_preference
        # - If template has NO leading comments but destination does, preserve destination's
        template_has_leading = anchor.template_start < template_node.location.start_line
        dest_has_leading = anchor.dest_start < dest_node.location.start_line

        if template_has_leading && @signature_match_preference == :template
          # Use template's leading comments
          (anchor.template_start...template_node.location.start_line).each do |line_num|
            line = @template_analysis.line_at(line_num)
            @result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_REPLACED,
              template_line: line_num,
            )
          end
        elsif dest_has_leading
          # Preserve destination's leading comments (either because preference is :destination,
          # or because template has none)
          (anchor.dest_start...dest_node.location.start_line).each do |line_num|
            line = @dest_analysis.line_at(line_num)
            @result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_KEPT_DEST,
              dest_line: line_num,
            )
          end
        end

        # Add the opening line (based on signature_match_preference)
        source_analysis = (@signature_match_preference == :template) ? @template_analysis : @dest_analysis
        source_node = (@signature_match_preference == :template) ? template_node : dest_node

        opening_line = source_analysis.line_at(source_node.location.start_line)
        @result.add_line(
          opening_line.chomp,
          decision: MergeResult::DECISION_REPLACED,
          template_line: ((@signature_match_preference == :template) ? source_node.location.start_line : nil),
          dest_line: ((@signature_match_preference == :destination) ? source_node.location.start_line : nil),
        )

        # Add the merged body (indented appropriately)
        merged_body.lines.each do |line|
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_REPLACED,
            template_line: nil,
            dest_line: nil,
          )
        end

        # Add the closing 'end'
        end_line = source_analysis.line_at(source_node.location.end_line)
        @result.add_line(
          end_line.chomp,
          decision: MergeResult::DECISION_REPLACED,
          template_line: ((@signature_match_preference == :template) ? source_node.location.end_line : nil),
          dest_line: ((@signature_match_preference == :destination) ? source_node.location.end_line : nil),
        )
      end

      # Extracts the body content of a node (without declaration and closing 'end').
      #
      # For class/module nodes, extracts content between the declaration line and the
      # closing 'end'. For conditional nodes, extracts the statements within the condition.
      #
      # @param node [Prism::Node] The node to extract body from
      # @param analysis [FileAnalysis] The file analysis containing the node
      # @return [String] The extracted body content
      #
      # @note Handles different node types:
      #   - ClassNode/ModuleNode: Uses node.body (StatementsNode)
      #   - IfNode/UnlessNode: Uses node.statements (StatementsNode)
      #   - CallNode with block: Uses node.block.body (StatementsNode)
      #
      # @api private
      def extract_node_body(node, analysis)
        # Get the statements node based on node type
        # Different node types store their body/statements in different attributes
        statements_node = case node
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::LambdaNode
          # These use .body which returns a StatementsNode
          node.body
        when Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode
          # These use .statements
          node.statements
        when Prism::CallNode
          # CallNode stores body inside block.body
          node.block&.body
        when Prism::BeginNode
          # BeginNode uses .statements for the main body
          node.statements
        when Prism::CaseNode, Prism::CaseMatchNode
          # Case nodes have conditions (WhenNode/InNode array), not a simple body
          # Return nil for now - these need special handling
          nil
        when Prism::ParenthesesNode
          node.body
        else
          # Try common patterns
          if node.respond_to?(:body)
            node.body
          elsif node.respond_to?(:statements)
            node.statements
          elsif node.respond_to?(:block) && node.block
            node.block.body
          end
        end

        return "" unless statements_node&.is_a?(Prism::StatementsNode)

        body_statements = statements_node.body
        return "" if body_statements.empty?

        # Get the line range of the body
        # Start from line after node opening (to include any leading comments/freeze markers)
        # For nodes with blocks, the body starts after the block opening
        body_start_line = case node
        when Prism::CallNode
          # Block body starts on line after the `do` or `{`
          node.block.opening_loc ? node.block.opening_loc.start_line + 1 : body_statements.first.location.start_line
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          # Body starts on line after class/module declaration
          node.location.start_line + 1
        else
          body_statements.first.location.start_line
        end

        last_stmt_line = body_statements.last.location.end_line

        # Extract the source lines for the body
        lines = []
        (body_start_line..last_stmt_line).each do |line_num|
          lines << analysis.line_at(line_num).chomp
        end
        lines.join("\n") + "\n"
      end
    end
  end
end
