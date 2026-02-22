# frozen_string_literal: true

module Prism
  module Merge
    # A merger that uses section-based semantics with recursive body merging for cleaner merging.
    #
    # SmartMerger:
    # 1. Converts each top-level node into a "section" identified by its signature
    # 2. Uses SectionTyping-style merge logic to decide which sections to include
    # 3. Recursively merges matching class/module/block bodies
    # 4. Outputs each selected node exactly once (with its comments)
    #
    # This approach avoids the complexity of tracking line ranges for anchors
    # and boundaries, which can lead to duplicate content when comments are
    # attached to multiple overlapping ranges.
    #
    # ## Merge Algorithm
    #
    # 1. Parse both template and destination files
    # 2. Generate signatures for all top-level nodes in both files
    # 3. Build a signature -> node map for destination
    # 4. Walk template nodes in order:
    #    - If signature matches a dest node:
    #      - If class/module/block with mergeable body: recursively merge bodies
    #      - Otherwise: output based on preference
    #    - If template-only: output if add_template_only_nodes is true
    # 5. Output any remaining dest-only nodes
    #
    # ## Recursive Body Merging
    #
    # When matching class/module definitions or CallNodes with blocks are found,
    # the merger recursively merges their body contents. This allows template
    # updates to nested methods/constants to be merged with destination customizations.
    #
    # @example Basic merge
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Template wins with additions
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      # @return [Integer, Float] Maximum recursion depth for body merging
      attr_reader :max_recursion_depth

      # @return [Hash, nil] Options to pass to Text::SmartMerger for comment-only files
      attr_reader :text_merger_options

      # Creates a new SmartMerger.
      #
      # @param template_content [String] Template Ruby source code
      # @param dest_content [String] Destination Ruby source code
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :template, :destination, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add template-only nodes
      # @param freeze_token [String, nil] Token for freeze block markers
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param max_recursion_depth [Integer, Float] Maximum depth for recursive body merging.
      #   Default: Float::INFINITY (no limit). This is a safety valve that users can set
      #   if they encounter edge cases.
      # @param current_depth [Integer] Current recursion depth (internal use)
      # @param match_refiner [#call, nil] Optional match refiner (unused but accepted for API compatibility)
      # @param regions [Array<Hash>, nil] Region configurations (unused but accepted for API compatibility)
      # @param region_placeholder [String, nil] Custom placeholder prefix (unused but accepted for API compatibility)
      # @param text_merger_options [Hash, nil] Options to pass to Text::SmartMerger when
      #   merging comment-only files (files with no Ruby code statements). Supported options:
      #   - :freeze_token - Token for freeze block markers (defaults to @freeze_token or "text-merge")
      #   - Any other options supported by Ast::Merge::Text::SmartMerger
      # @param options [Hash] Additional options for forward compatibility
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        freeze_token: nil,
        node_typing: nil,
        max_recursion_depth: Float::INFINITY,
        current_depth: 0,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        text_merger_options: nil,
        **options
      )
        @max_recursion_depth = max_recursion_depth
        @current_depth = current_depth
        @text_merger_options = text_merger_options

        # Wrap signature_generator to include node_typing processing
        effective_signature_generator = build_effective_signature_generator(signature_generator, node_typing)

        super(
          template_content,
          dest_content,
          signature_generator: effective_signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
        )
      end

      # Determine whether the given analysis represents a comment-only file.
      #
      # Returns true when every top-level statement is a comment/block/empty
      # node produced by the comment parsers. This is used to decide whether to
      # delegate to the comment-only merger logic.
      #
      # @param analysis [FileAnalysis]
      # @return [Boolean]
      def comment_only_file?(analysis)
        stmts = analysis.statements
        return false if stmts.nil? || stmts.empty?

        stmts.all? do |s|
          # AST comment nodes (Prism-specific ones inherit from these)
          s.is_a?(Ast::Merge::Comment::Empty) ||
            s.is_a?(Ast::Merge::Comment::Block) ||
            s.is_a?(Ast::Merge::Comment::Line)
        end
      end

      # Perform the merge and return a hash with content, debug info, and statistics.
      #
      # @return [Hash] Hash with :content, :debug, and :statistics keys
      def merge_with_debug
        result_obj = merge_result
        {
          content: result_obj.to_s,
          debug: {
            template_statements: @template_analysis&.statements&.size || 0,
            dest_statements: @dest_analysis&.statements&.size || 0,
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            freeze_token: @freeze_token,
          },
          statistics: result_obj.respond_to?(:statistics) ? result_obj.statistics : result_obj.decision_summary,
        }
      end

      protected

      # @return [Class] The analysis class for Ruby files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token for Ruby
      def default_freeze_token
        "prism-merge"
      end

      # @return [Class] The result class for Ruby files
      def result_class
        MergeResult
      end

      # @return [Class, nil] No aligner needed for SmartMerger
      def aligner_class
        nil
      end

      # @return [Class, nil] No resolver needed for SmartMerger
      def resolver_class
        nil
      end

      # Build the result with analysis references
      def build_result
        MergeResult.new(
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        )
      end

      # @return [Class] The template parse error class for Ruby
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for Ruby
      def destination_parse_error_class
        DestinationParseError
      end

      # Perform the SmartMerger's section-based merge with recursive body merging.
      #
      # The algorithm processes nodes in destination order to preserve user additions
      # in their original positions, while injecting template-only nodes at the beginning.
      #
      # For comment-only files (no Ruby code statements), FileAnalysis parses the content
      # into Comment::Block and Comment::Empty nodes. We detect this case by checking if
      # ALL statements are comment nodes, and delegate to merge_comment_only_files.
      #
      # @return [MergeResult] The merge result
      def perform_merge
        validate_files!

        # Handle special case: files that are comment-only (no code statements)
        if comment_only_file?(@template_analysis) && comment_only_file?(@dest_analysis)
          return merge_comment_only_files
        end

        # Build signature maps for quick lookup
        template_by_signature = build_signature_map(@template_analysis)
        dest_by_signature = build_signature_map(@dest_analysis)

        # Track which signatures we've output (to avoid duplicates)
        output_signatures = Set.new

        # Track which dest line ranges have been output (to avoid duplicating nested content)
        output_dest_line_ranges = []

        # Phase 1: Output template-only nodes first (nodes in template but not in dest)
        # This ensures template-only nodes (like `source` in Gemfiles) appear at the top
        if @add_template_only_nodes
          @template_analysis.statements.each do |template_node|
            template_signature = @template_analysis.generate_signature(template_node)

            # Skip if this template node has a match in dest
            next if template_signature && dest_by_signature.key?(template_signature)

            # Template-only node - output it at its template position
            add_node_to_result(@result, template_node, @template_analysis, :template)
            output_signatures << template_signature if template_signature
          end
        end

        # Phase 2: Process dest nodes in their original order
        # This preserves dest-only nodes in their original position relative to matched nodes

        # Emit prefix lines from the dest source (magic comments, blank lines before first node)
        last_output_dest_line = emit_dest_prefix_lines(@result, @dest_analysis)

        @dest_analysis.statements.each do |dest_node|
          dest_signature = @dest_analysis.generate_signature(dest_node)

          # Skip if already output
          next if dest_signature && output_signatures.include?(dest_signature)

          # Skip if this dest node is inside a dest range we've already output
          node_range = dest_node.location.start_line..dest_node.location.end_line
          next if output_dest_line_ranges.any? { |range| range.cover?(node_range.begin) && range.cover?(node_range.end) }

          # Emit inter-node gap lines from the dest source (blank lines between blocks)
          last_output_dest_line = emit_dest_gap_lines(@result, @dest_analysis, last_output_dest_line, dest_node)

          if dest_signature && template_by_signature.key?(dest_signature)
            # Matched node - merge with template version
            template_node = template_by_signature[dest_signature]
            output_signatures << dest_signature

            # Track the dest node's line range to avoid re-outputting it later
            output_dest_line_ranges << node_range

            if should_merge_recursively?(template_node, dest_node)
              # Recursively merge class/module/block bodies
              merge_node_body_recursively(template_node, dest_node)
            else
              # Output based on preference
              node_preference = preference_for_node(template_node, dest_node)

              if node_preference == :template
                add_node_to_result(@result, template_node, @template_analysis, :template)
              else
                add_node_to_result(@result, dest_node, @dest_analysis, :destination)
              end
            end
          else
            # Dest-only node - output it in its original position
            add_node_to_result(@result, dest_node, @dest_analysis, :destination)
            output_dest_line_ranges << node_range
            output_signatures << dest_signature if dest_signature
          end

          # Update last_output_dest_line to track trailing blank line from add_node_to_result
          last_output_dest_line = dest_node.location.end_line
          trailing_line = last_output_dest_line + 1
          trailing_content = @dest_analysis.line_at(trailing_line)
          last_output_dest_line = trailing_line if trailing_content && trailing_content.strip.empty?
        end

        @result
      end

      private

      # Check if a node has a freeze marker in its leading comments OR
      # contains a freeze marker anywhere in its content.
      #
      # Nodes with freeze markers always prefer destination version during merge.
      # This ensures that:
      # 1. Top-level nodes with freeze markers as leading comments are preserved
      # 2. Nodes containing freeze markers in their body (e.g., inside blocks) are preserved
      # 3. Already-wrapped FrozenWrapper nodes are recognized as frozen
      #
      # @param node [Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper] The node to check
      # @return [Boolean] true if the node has or contains a freeze marker
      def frozen_node?(node)
        # Already wrapped as frozen (includes Freezable module)
        return true if node.is_a?(Ast::Merge::Freezable)

        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # Check for freeze marker in leading comments
        if actual_node.respond_to?(:location) && actual_node.location.respond_to?(:leading_comments)
          return true if actual_node.location.leading_comments.any? { |c| c.slice.match?(freeze_pattern) }
        end

        # Check if node content contains a freeze marker (for nested freeze blocks)
        if actual_node.respond_to?(:slice)
          return true if actual_node.slice.match?(freeze_pattern)
        end

        false
      end

      # Check if a node contains freeze blocks within its body/content.
      #
      # This is used to detect if a class, module, block, or other container
      # has freeze markers anywhere inside it (not just as a leading comment).
      #
      # @param node [Prism::Node] The node to check
      # @param analysis [FileAnalysis] The file analysis (for context)
      # @return [Boolean] true if the node contains freeze markers
      def node_contains_freeze_blocks?(node, analysis = nil)
        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # Check if node content contains a freeze marker
        if actual_node.respond_to?(:slice)
          return true if actual_node.slice.match?(freeze_pattern)
        end

        false
      end

      def validate_files!
        unless @template_analysis.valid?
          raise TemplateParseError.new(
            "Template file has parsing errors",
            content: @template_content,
            parse_result: @template_analysis.parse_result,
          )
        end

        unless @dest_analysis.valid?
          raise DestinationParseError.new(
            "Destination file has parsing errors",
            content: @dest_content,
            parse_result: @dest_analysis.parse_result,
          )
        end
      end

      # Handle merging of files that contain only comments (no code statements).
      #
      # For comment-only files (like files with just `# frozen_string_literal: true`),
      # there are no Prism AST nodes to match. We use Prism::Merge::Comment::Parser
      # to parse comments into AST nodes, then apply the same two-phase merge algorithm
      # used by perform_merge:
      #
      # Phase 1: Process template comment nodes in order
      #   - Match by signature (normalized content)
      #   - Apply preference for matched pairs
      #   - Add template-only nodes if add_template_only_nodes is true
      #
      # Phase 2: Add dest-only comment nodes
      #   - Preserves user additions (comments not in template)
      #   - Uses index-based tracking to preserve duplicate comments
      #
      # This ensures consistent preference-based behavior across all merge operations.
      # Comment nodes match by their normalized content (signature). When multiple
      # dest nodes have the same signature, only the first matches; the rest are
      # treated as dest-only and preserved in Phase 2.
      #
      # @return [MergeResult] The merge result
      def merge_comment_only_files
        # Parse comments into AST nodes
        template_lines = @template_content.lines.map(&:chomp)
        dest_lines = @dest_content.lines.map(&:chomp)

        template_nodes = Comment::Parser.parse(template_lines)
        dest_nodes = Comment::Parser.parse(dest_lines)

        # Build signature -> [indices] map for dest nodes (to find first unmatched)
        dest_indices_by_signature = build_comment_indices_map(dest_nodes)

        # Track which template signatures we've output (to avoid duplicate template nodes)
        output_template_signatures = Set.new

        # Track which dest node indices have been matched (to preserve unmatched duplicates)
        matched_dest_indices = Set.new

        # Phase 1: Process template nodes in their original order
        template_nodes.each do |template_node|
          template_signature = template_node.respond_to?(:signature) ? template_node.signature : nil

          # Skip if this template signature was already output
          next if template_signature && output_template_signatures.include?(template_signature)

          # Find first unmatched dest node with same signature
          dest_index = find_first_unmatched_index(dest_indices_by_signature, template_signature, matched_dest_indices)

          if dest_index
            # Matched node - apply preference
            dest_node = dest_nodes[dest_index]
            matched_dest_indices << dest_index
            output_template_signatures << template_signature if template_signature

            # Use preference to decide which version to output
            if default_preference == :template
              add_comment_node_to_result(template_node, :template)
            else
              add_comment_node_to_result(dest_node, :destination)
            end
          elsif @add_template_only_nodes || (default_preference == :template && template_node.respond_to?(:magic_comment?) && template_node.magic_comment?)
            # Template-only node - output it at its template position
            # Magic comments are ALWAYS output from template when preference is :template
            # to ensure they remain at the top of the file
            add_comment_node_to_result(template_node, :template)
            output_template_signatures << template_signature if template_signature
          end
        end

        # Phase 2: Add dest-only nodes (nodes not matched in Phase 1)
        # Only add dest-only nodes when preference is :destination (to preserve user additions)
        # When preference is :template, we only want template content
        if default_preference == :destination
          dest_nodes.each_with_index do |dest_node, index|
            next if matched_dest_indices.include?(index)

            # Dest-only node - output it
            add_comment_node_to_result(dest_node, :destination)
          end
        end

        @result
      end

      # Build a map of signature -> [indices] for comment nodes.
      #
      # @param nodes [Array<Ast::Merge::Comment::*>] Comment nodes
      # @return [Hash{Array => Array<Integer>}] Map of signatures to node indices
      def build_comment_indices_map(nodes)
        map = Hash.new { |h, k| h[k] = [] }
        nodes.each_with_index do |node, index|
          sig = node.respond_to?(:signature) ? node.signature : nil
          map[sig] << index if sig
        end
        map
      end

      # Find the first unmatched index for a given signature.
      #
      # @param indices_map [Hash] Map of signature -> [indices]
      # @param signature [Array, nil] The signature to look up
      # @param matched_indices [Set] Already matched indices
      # @return [Integer, nil] First unmatched index or nil
      def find_first_unmatched_index(indices_map, signature, matched_indices)
        return unless signature
        indices = indices_map[signature]
        return unless indices
        indices.find { |i| !matched_indices.include?(i) }
      end

      # Add a comment node to the result.
      #
      # @param node [Ast::Merge::Comment::*] The comment node
      # @param source [Symbol] :template or :destination
      def add_comment_node_to_result(node, source)
        decision = (source == :template) ? MergeResult::DECISION_KEPT_TEMPLATE : MergeResult::DECISION_KEPT_DEST

        content = if node.respond_to?(:text)
          node.text
        elsif node.respond_to?(:content)
          node.content
        else
          node.to_s
        end

        # Handle Block nodes that contain multiple lines
        if node.respond_to?(:children) && node.children.any?
          node.children.each do |child|
            child_content = child.respond_to?(:text) ? child.text : child.to_s
            line_num = child.respond_to?(:line_number) ? child.line_number : nil
            if source == :template
              @result.add_line(child_content, decision: decision, template_line: line_num)
            else
              @result.add_line(child_content, decision: decision, dest_line: line_num)
            end
          end
        else
          line_num = node.respond_to?(:line_number) ? node.line_number : nil
          if source == :template
            @result.add_line(content, decision: decision, template_line: line_num)
          else
            @result.add_line(content, decision: decision, dest_line: line_num)
          end
        end
      end

      # Build a map of signature -> node for an analysis.
      #
      # @param analysis [FileAnalysis] The file analysis
      # @return [Hash{Array => Prism::Node}] Map of signatures to nodes
      def build_signature_map(analysis)
        map = {}
        analysis.statements.each do |node|
          sig = analysis.generate_signature(node)
          # Only map nodes with signatures, and keep first occurrence
          map[sig] ||= node if sig
        end
        map
      end

      # Determine preference for a specific node pair.
      #
      # Frozen nodes (those with freeze markers in leading_comments) always
      # prefer the destination version, as they represent user customizations
      # that should be preserved across template updates.
      #
      # @param template_node [Prism::Node] Template node
      # @param dest_node [Prism::Node] Destination node
      # @return [Symbol] :template or :destination
      def preference_for_node(template_node, dest_node)
        # Frozen nodes always prefer destination - they're user customizations
        return :destination if frozen_node?(dest_node)

        return @preference unless @preference.is_a?(Hash)

        # Process nodes through node_typing if configured
        typed_template = @node_typing ? ::Ast::Merge::NodeTyping.process(template_node, @node_typing) : template_node
        typed_dest = @node_typing ? ::Ast::Merge::NodeTyping.process(dest_node, @node_typing) : dest_node

        # Check for merge_type from NodeTyping
        if ::Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        if ::Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        default_preference
      end

      def default_preference
        if @preference.is_a?(Hash)
          @preference.fetch(:default, :destination)
        else
          @preference
        end
      end

      # Build an effective signature generator that incorporates node_typing.
      #
      # When node_typing is provided, this wraps the signature_generator (or creates one)
      # to process nodes through node_typing first. This allows:
      #
      # - Custom signature_generators to receive typed nodes with merge_type
      # - Default signature generation to work with the underlying node (via unwrap in
      #   FileAnalyzable#generate_signature)
      #
      # The node_typing processing happens here (for signature generation) AND in
      # preference_for_node (for preference determination), so typed nodes are handled
      # consistently in both contexts.
      #
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param node_typing [Hash, nil] Node typing configuration
      # @return [Proc, nil] Combined signature generator, or nil if neither is provided
      def build_effective_signature_generator(signature_generator, node_typing)
        return signature_generator unless node_typing

        ->(node) {
          # First, process through node_typing to potentially add merge_type
          processed_node = ::Ast::Merge::NodeTyping.process(node, node_typing)

          # Then, pass to signature_generator or return processed node for default handling
          # FileAnalyzable#generate_signature will unwrap Wrappers for default signature computation
          if signature_generator
            signature_generator.call(processed_node)
          else
            processed_node
          end
        }
      end

      # Emit prefix lines from the destination source that appear before the first node.
      # This preserves magic comments (e.g., `# frozen_string_literal: true`) and blank
      # lines that precede any AST statements.
      #
      # @param result [MergeResult] The merge result
      # @param analysis [FileAnalysis] The destination file analysis
      # @return [Integer] The last line number emitted (0 if none)
      def emit_dest_prefix_lines(result, analysis)
        return 0 if analysis.statements.empty?

        first_node = analysis.statements.first
        # Find the first line of content: either leading comment or node start
        leading_comments = first_node.location.respond_to?(:leading_comments) ? first_node.location.leading_comments : []
        first_content_line = leading_comments.any? ? leading_comments.first.location.start_line : first_node.location.start_line

        return 0 if first_content_line <= 1

        # Emit lines before the first node (magic comments, blank lines)
        last_emitted = 0
        (1...first_content_line).each do |line_num|
          line = analysis.line_at(line_num)&.chomp || ""
          result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
          last_emitted = line_num
        end
        last_emitted
      end

      # Emit blank/gap lines from the destination source between the last output line
      # and the next node (including its leading comments). This preserves blank lines
      # that separate top-level blocks.
      #
      # @param result [MergeResult] The merge result
      # @param analysis [FileAnalysis] The destination file analysis
      # @param last_output_line [Integer] The last dest line number that was output
      # @param next_node [Prism::Node] The next node about to be output
      # @return [Integer] The updated last output line number
      def emit_dest_gap_lines(result, analysis, last_output_line, next_node)
        return last_output_line if last_output_line == 0

        # Find where the next node's content starts (leading comment or node itself)
        leading_comments = next_node.location.respond_to?(:leading_comments) ? next_node.location.leading_comments : []
        next_start_line = leading_comments.any? ? leading_comments.first.location.start_line : next_node.location.start_line

        # Emit gap lines (blank lines between last output and next node)
        gap_start = last_output_line + 1
        return last_output_line if gap_start >= next_start_line

        (gap_start...next_start_line).each do |line_num|
          line = analysis.line_at(line_num)&.chomp || ""
          # Only emit blank lines in the gap (don't re-emit content)
          next unless line.strip.empty?

          result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
        end

        last_output_line
      end

      # Add a node to the result, including its leading and trailing comments.
      #
      # @param result [MergeResult] The merge result
      # @param node [Prism::Node] The node to add
      # @param analysis [FileAnalysis] The source analysis
      # @param source [Symbol] :template or :destination
      def add_node_to_result(result, node, analysis, source)
        decision = case source
        when :template
          MergeResult::DECISION_KEPT_TEMPLATE
        else
          MergeResult::DECISION_KEPT_DEST
        end

        # Get leading comments attached to the node
        leading_comments = node.location.respond_to?(:leading_comments) ? node.location.leading_comments : []

        # Add leading comments first (includes freeze markers if present)
        # Also add any blank lines between consecutive comments
        prev_comment_line = nil
        leading_comments.each do |comment|
          line_num = comment.location.start_line

          # Add blank lines between this comment and the previous one
          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              line = analysis.line_at(blank_line_num)&.chomp || ""
              if source == :template
                result.add_line(line, decision: decision, template_line: blank_line_num)
              else
                result.add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end

          prev_comment_line = line_num
        end

        # Add blank line before node if there's a gap after comments
        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          if node.location.start_line > last_comment_line + 1
            # There's a gap - add blank lines
            ((last_comment_line + 1)...node.location.start_line).each do |line_num|
              line = analysis.line_at(line_num)&.chomp || ""
              if source == :template
                result.add_line(line, decision: decision, template_line: line_num)
              else
                result.add_line(line, decision: decision, dest_line: line_num)
              end
            end
          end
        end

        # Add node source lines
        (node.location.start_line..node.location.end_line).each do |line_num|
          line = analysis.line_at(line_num)&.chomp || ""

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end
        end

        # Add trailing blank line if needed for separation
        trailing_line = node.location.end_line + 1
        trailing_content = analysis.line_at(trailing_line)
        if trailing_content && trailing_content.strip.empty?
          if source == :template
            result.add_line("", decision: decision, template_line: trailing_line)
          else
            result.add_line("", decision: decision, dest_line: trailing_line)
          end
        end

        # Add trailing comments attached to the node (e.g., end-of-file comments)
        trailing_comments = node.location.respond_to?(:trailing_comments) ? node.location.trailing_comments : []
        trailing_comments.each do |comment|
          line_num = comment.location.start_line
          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end
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
      #   - Nodes of different types
      #   - Blocks whose body contains only literals/expressions with no mergeable statements
      #   - When max_recursion_depth has been reached (safety valve)
      def should_merge_recursively?(template_node, dest_node)
        return false unless template_node && dest_node

        # Safety valve: stop recursion if max depth reached
        return false if @current_depth >= @max_recursion_depth

        # Unwrap FrozenWrapper nodes to check the actual node type
        actual_template = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
        actual_dest = dest_node.respond_to?(:unwrap) ? dest_node.unwrap : dest_node

        # Both nodes must be the same type
        return false unless actual_template.class == actual_dest.class

        # Determine if this node type supports recursive merging
        case actual_template
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          # Class/module definitions - merge their body contents
          true
        when Prism::CallNode
          # Only merge if both have blocks with mergeable content
          return false unless actual_template.block && actual_dest.block

          body_has_mergeable_statements?(actual_template.block.body) &&
            body_has_mergeable_statements?(actual_dest.block.body)
        when Prism::BeginNode
          # begin/rescue/ensure blocks - merge statements if both have them
          !!(actual_template.statements && actual_dest.statements)
        else
          false
        end
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

      # Recursively merges the body of matching class, module, or call-with-block nodes.
      #
      # This method extracts the body content (everything between the opening
      # declaration and the closing 'end'), creates a new nested SmartMerger to merge
      # those bodies, and then reassembles the complete node with the merged body.
      #
      # @param template_node [Prism::Node] Node from template
      # @param dest_node [Prism::Node] Node from destination
      #
      # @note The nested merger is configured with:
      #   - Same signature_generator, preference, add_template_only_nodes, and freeze_token
      #   - Incremented current_depth to track recursion level
      #
      # @api private
      def merge_node_body_recursively(template_node, dest_node)
        # Unwrap FrozenWrapper nodes to get actual nodes
        actual_template = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
        actual_dest = dest_node.respond_to?(:unwrap) ? dest_node.unwrap : dest_node

        # Extract the body source for both nodes
        template_body = extract_node_body(actual_template, @template_analysis)
        dest_body = extract_node_body(actual_dest, @dest_analysis)

        # Recursively merge the bodies with incremented depth
        body_merger = SmartMerger.new(
          template_body,
          dest_body,
          signature_generator: @template_analysis.instance_variable_get(:@signature_generator),
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          freeze_token: @freeze_token,
          max_recursion_depth: @max_recursion_depth,
          current_depth: @current_depth + 1,
          node_typing: @node_typing,
        )
        merged_body = body_merger.merge.rstrip

        # Get preference for this specific node pair
        node_preference = preference_for_node(template_node, dest_node)

        # Determine which comments to use:
        # - If template preference and template has comments, use template's
        # - If template preference but template has NO comments, preserve dest's comments
        # - If dest preference, use dest's comments
        template_comments = actual_template.location.respond_to?(:leading_comments) ? actual_template.location.leading_comments : []
        dest_comments = actual_dest.location.respond_to?(:leading_comments) ? actual_dest.location.leading_comments : []

        # Choose comment source: prefer dest comments if template has none (to preserve existing headers)
        if node_preference == :template && template_comments.empty? && dest_comments.any?
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = @dest_analysis
        elsif node_preference == :template
          comment_source = :template
          leading_comments = template_comments
          comment_analysis = @template_analysis
        else
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = @dest_analysis
        end

        # Source for the opening/closing lines follows node_preference
        source_analysis = (node_preference == :template) ? @template_analysis : @dest_analysis
        source_node = (node_preference == :template) ? actual_template : actual_dest
        decision = MergeResult::DECISION_REPLACED

        # Add leading comments with blank lines between them preserved
        prev_comment_line = nil
        leading_comments.each do |comment|
          line_num = comment.location.start_line

          # Add blank lines between this comment and the previous one
          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              line = comment_analysis.line_at(blank_line_num)&.chomp || ""
              if comment_source == :template
                @result.add_line(line, decision: decision, template_line: blank_line_num)
              else
                @result.add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          line = comment_analysis.line_at(line_num)&.chomp || comment.slice.rstrip
          if comment_source == :template
            @result.add_line(line, decision: decision, template_line: line_num)
          else
            @result.add_line(line, decision: decision, dest_line: line_num)
          end

          prev_comment_line = line_num
        end

        # Add a single blank line between comments and node if needed for separation.
        # IMPORTANT: We only add a blank line, not content from either source.
        # When comments come from dest but node comes from template (or vice versa),
        # filling the "gap" with lines from the comment source would incorrectly
        # include unrelated content (potentially entire nodes) from that source.
        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          # Only add blank line if there's a gap and we need separation
          if source_node.location.start_line > last_comment_line + 1
            @result.add_line("", decision: decision)
          end
        end

        # Add the opening line (based on preference)
        opening_line = source_analysis.line_at(source_node.location.start_line)
        @result.add_line(
          opening_line.chomp,
          decision: decision,
          template_line: (node_preference == :template) ? source_node.location.start_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.start_line : nil,
        )

        # Add the merged body
        merged_body.lines.each do |line|
          @result.add_line(
            line.chomp,
            decision: decision,
            template_line: nil,
            dest_line: nil,
          )
        end

        # Add the closing 'end'
        end_line = source_analysis.line_at(source_node.location.end_line)
        @result.add_line(
          end_line.chomp,
          decision: decision,
          template_line: (node_preference == :template) ? source_node.location.end_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.end_line : nil,
        )
      end

      # Extracts the body content of a node (without declaration and closing 'end').
      #
      # @param node [Prism::Node] The node to extract body from
      # @param analysis [FileAnalysis] The file analysis containing the node
      # @return [String] The extracted body content
      #
      # @api private
      def extract_node_body(node, analysis)
        # Get the statements node based on node type
        statements_node = case node
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::LambdaNode
          node.body
        when Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode
          node.statements
        when Prism::CallNode
          node.block&.body
        when Prism::BeginNode
          node.statements
        when Prism::ParenthesesNode
          node.body
        else
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
        body_start_line = case node
        when Prism::CallNode
          node.block.opening_loc ? node.block.opening_loc.start_line + 1 : body_statements.first.location.start_line
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          node.location.start_line + 1
        else
          body_statements.first.location.start_line
        end

        body_end_line = case node
        when Prism::CallNode
          node.block.closing_loc ? node.block.closing_loc.start_line - 1 : body_statements.last.location.end_line
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          node.end_keyword_loc ? node.end_keyword_loc.start_line - 1 : body_statements.last.location.end_line
        else
          body_statements.last.location.end_line
        end

        # Extract the source lines for the body
        lines = []
        (body_start_line..body_end_line).each do |line_num|
          lines << analysis.line_at(line_num).chomp
        end
        lines.join("\n") + "\n"
      end
    end
  end
end
