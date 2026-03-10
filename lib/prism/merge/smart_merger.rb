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
        @dest_prefix_comment_lines = nil

        # Store the raw (unwrapped) signature_generator so that
        # merge_node_body_recursively can pass it to inner SmartMergers
        # without double-wrapping.
        @raw_signature_generator = signature_generator

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

        # Track consumed individual template node indices (not just signatures)
        # so that multiple nodes with the same signature are matched 1:1 in
        # order rather than collapsed.
        consumed_template_indices = Set.new
        # Per-signature cursor for sequential matching of duplicates
        sig_cursor = Hash.new(0)

        # Track which dest line ranges have been output (to avoid duplicating nested content)
        output_dest_line_ranges = []

        # Emit dest magic comments first — they must always be at the very
        # top of the output, before any template-only nodes from Phase 1.
        last_output_dest_line = emit_dest_prefix_lines(@result, @dest_analysis)

        # Phase 1: Output template-only nodes first (nodes in template but not in dest)
        # This ensures template-only nodes (like `source` in Gemfiles) appear at the top
        if @add_template_only_nodes
          @template_analysis.statements.each_with_index do |template_node, t_idx|
            template_signature = @template_analysis.generate_signature(template_node)

            # Skip if this template node has a match in dest
            next if template_signature && dest_by_signature.key?(template_signature)

            # Template-only node - output it at its template position
            add_node_to_result(@result, template_node, @template_analysis, :template)
            consumed_template_indices << t_idx
          end
        end

        # Phase 2: Process dest nodes in their original order
        # This preserves dest-only nodes in their original position relative to matched nodes

        @dest_analysis.statements.each do |dest_node|
          dest_signature = @dest_analysis.generate_signature(dest_node)

          # Skip if this dest node is inside a dest range we've already output
          node_range = dest_node.location.start_line..dest_node.location.end_line
          next if output_dest_line_ranges.any? { |range| range.cover?(node_range.begin) && range.cover?(node_range.end) }

          # Emit inter-node gap lines from the dest source (blank lines between blocks)
          last_output_dest_line = emit_dest_gap_lines(@result, @dest_analysis, last_output_dest_line, dest_node)

          # Track which source/analysis was used for output so we can check
          # whether a trailing blank was emitted from that source's analysis.
          output_node = dest_node
          output_analysis = @dest_analysis

          if dest_signature && template_by_signature.key?(dest_signature)
            # Find the next unconsumed template node with this signature
            candidates = template_by_signature[dest_signature]
            cursor = sig_cursor[dest_signature]
            template_info = nil

            while cursor < candidates.size
              candidate = candidates[cursor]
              unless consumed_template_indices.include?(candidate[:index])
                template_info = candidate
                break
              end
              cursor += 1
            end

            if template_info
              template_node = template_info[:node]
              consumed_template_indices << template_info[:index]
              sig_cursor[dest_signature] = cursor + 1

              # Track the dest node's line range to avoid re-outputting it later
              output_dest_line_ranges << node_range

              if should_merge_recursively?(template_node, dest_node)
                # Recursively merge class/module/block bodies
                recursive_emission = merge_node_body_recursively(template_node, dest_node)
                node_pref = preference_for_node(template_node, dest_node)
                if node_pref == :template
                  output_node = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
                  output_analysis = @template_analysis
                end

                if recursive_emission&.dig(:last_emitted_dest_line)
                  last_output_dest_line = [last_output_dest_line, recursive_emission[:last_emitted_dest_line]].max
                end
              else
                # Output based on preference
                node_preference = preference_for_node(template_node, dest_node)
                fallback_emission = nil

                if node_preference == :template
                  fallback_emission = add_matched_template_node_to_result(@result, template_node, dest_node)
                  output_node = template_node
                  output_analysis = @template_analysis
                else
                  add_node_to_result(@result, dest_node, @dest_analysis, :destination)
                end

                if fallback_emission&.dig(:last_emitted_dest_line)
                  last_output_dest_line = [last_output_dest_line, fallback_emission[:last_emitted_dest_line]].max
                end
              end
            else
              # All template copies with this signature consumed — dest-only duplicate
              add_node_to_result(@result, dest_node, @dest_analysis, :destination)
              output_dest_line_ranges << node_range
            end
          else
            # Dest-only node - output it in its original position
            add_node_to_result(@result, dest_node, @dest_analysis, :destination)
            output_dest_line_ranges << node_range
          end

          # Update last_output_dest_line. Advance past the trailing blank
          # only if the output source actually has a trailing blank (meaning
          # add_node_to_result / merge_node_body_recursively emitted it).
          last_output_dest_line = dest_node.location.end_line
          actual_output_end = output_node.respond_to?(:unwrap) ? output_node.unwrap.location.end_line : output_node.location.end_line
          trailing_line_num = actual_output_end + 1
          trailing_content = output_analysis.line_at(trailing_line_num)
          if trailing_content && trailing_content.strip.empty?
            # The output source had a trailing blank that was emitted.
            # Advance last_output_dest_line so emit_dest_gap_lines doesn't re-emit it.
            trailing_dest_line = dest_node.location.end_line + 1
            dest_trailing = @dest_analysis.line_at(trailing_dest_line)
            last_output_dest_line = trailing_dest_line if dest_trailing && dest_trailing.strip.empty?
          end
        end

        @result
      end

      private

      # Check if a node has a freeze marker in its leading comments.
      #
      # Nodes with freeze markers always prefer destination version during merge.
      # This ensures that:
      # 1. Top-level nodes with freeze markers as leading comments are preserved
      # 2. Nested freeze markers do NOT freeze the outer container
      # 3. Already-wrapped FrozenWrapper nodes are recognized as frozen
      #
      # @param node [Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper] The node to check
      # @return [Boolean] true if the node has a direct freeze marker
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
        @comment_only_prefix_lines = {
          template: Set.new,
          destination: Set.new,
        }

        # Parse comments into AST nodes
        template_lines = @template_content.lines.map(&:chomp)
        dest_lines = @dest_content.lines.map(&:chomp)

        emit_comment_only_prefix_lines(template_lines, dest_lines)

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
        suppressed_lines = @comment_only_prefix_lines&.fetch(source, Set.new) || Set.new

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
            next if line_num && suppressed_lines.include?(line_num)

            if source == :template
              @result.add_line(child_content, decision: decision, template_line: line_num)
            else
              @result.add_line(child_content, decision: decision, dest_line: line_num)
            end
          end
        else
          line_num = node.respond_to?(:line_number) ? node.line_number : nil
          return if line_num && suppressed_lines.include?(line_num)

          if source == :template
            @result.add_line(content, decision: decision, template_line: line_num)
          else
            @result.add_line(content, decision: decision, dest_line: line_num)
          end
        end
      end

      def emit_comment_only_prefix_lines(template_lines, dest_lines)
        dest_prefix = comment_only_prefix_lines(dest_lines)
        return if dest_prefix[:entries].empty?

        dest_prefix[:entries].each do |entry|
          @result.add_line(entry[:text], decision: MergeResult::DECISION_KEPT_DEST, dest_line: entry[:line_num])
        end
        dest_prefix[:suppressed_line_nums].each { |line_num| @comment_only_prefix_lines[:destination] << line_num }

        template_prefix = comment_only_prefix_lines(template_lines)
        template_prefix[:suppressed_line_nums].each { |line_num| @comment_only_prefix_lines[:template] << line_num }
      end

      def comment_only_prefix_lines(lines)
        entries = []
        suppressed_line_nums = Set.new
        index = 0
        pending_blanks = []
        saw_magic = false
        seen_magic_types = Set.new

        if lines.first&.start_with?("#!")
          entries << {line_num: 1, text: lines.first.to_s, kind: :shebang}
          suppressed_line_nums << 1
          index = 1
        end

        while index < lines.length
          line_num = index + 1
          line = lines[index].to_s
          stripped = line.rstrip

          if stripped.empty?
            pending_blanks << {line_num: line_num, text: line, kind: :blank}
            index += 1
            next
          end

          magic_type = ruby_magic_comment_line_type(stripped)
          break unless magic_type

          unless seen_magic_types.include?(magic_type)
            entries.concat(pending_blanks)
            pending_blanks.each { |entry| suppressed_line_nums << entry[:line_num] }
            entries << {line_num: line_num, text: stripped, kind: :magic}
            seen_magic_types << magic_type
          end

          pending_blanks = []
          suppressed_line_nums << line_num
          saw_magic = true
          index += 1
        end

        if saw_magic
          entries.concat(pending_blanks)
          pending_blanks.each { |entry| suppressed_line_nums << entry[:line_num] }
        end

        {
          entries: entries,
          suppressed_line_nums: suppressed_line_nums,
        }
      end

      def ruby_magic_comment_line?(line)
        !!ruby_magic_comment_line_type(line)
      end

      def ruby_magic_comment_line_type(line)
        text = line.sub(/\A#\s*/, "").strip
        Comment::Line::MAGIC_COMMENT_PATTERNS.each do |type, pattern|
          return type if text.match?(pattern)
        end

        nil
      end

      # Build a map of signature -> node for an analysis.
      #
      # @param analysis [FileAnalysis] The file analysis
      # @return [Hash{Array => Prism::Node}] Map of signatures to nodes
      def build_signature_map(analysis)
        map = Hash.new { |h, k| h[k] = [] }
        analysis.statements.each_with_index do |node, idx|
          sig = analysis.generate_signature(node)
          map[sig] << {node: node, index: idx} if sig
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

      # Emit destination magic comments and any lines that precede the first
      # AST node's leading comments.
      #
      # Magic comments (frozen_string_literal, encoding, etc.) are file-level
      # metadata managed by Prism. The destination is the real file on disk,
      # so its magic comments must always be preserved — regardless of merge
      # preference. This method:
      #
      # 1. Emits any lines before the first leading comment (shebangs, etc.)
      # 2. Emits magic comments from the first dest node's leading comments
      # 3. Emits blank lines between the last magic comment and the first
      #    non-magic leading comment (or the node itself)
      # 4. Records which dest line numbers were emitted so that
      #    add_node_to_result can skip them (preventing duplication)
      #
      # @param result [MergeResult] The merge result
      # @param analysis [FileAnalysis] The destination file analysis
      # @return [Integer] The last line number emitted (0 if none)
      def emit_dest_prefix_lines(result, analysis)
        @dest_prefix_comment_lines = Set.new
        return 0 if analysis.statements.empty?

        first_node = analysis.statements.first
        leading_comments = first_node.location.respond_to?(:leading_comments) ? first_node.location.leading_comments : []
        first_content_line = leading_comments.any? ? leading_comments.first.location.start_line : first_node.location.start_line

        last_emitted = 0

        # Step 1: Emit lines before first leading comment (shebangs, etc.)
        if first_content_line > 1
          (1...first_content_line).each do |line_num|
            line = analysis.line_at(line_num)&.chomp || ""
            result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
            @dest_prefix_comment_lines << line_num
            last_emitted = line_num
          end
        end

        # Step 2: Emit contiguous magic comments from the top of the
        # leading comments list, plus blank lines between them and the
        # next non-magic content.
        magic_end_index = -1
        leading_comments.each_with_index do |comment, idx|
          break unless prism_magic_comment?(comment)
          magic_end_index = idx
        end

        return last_emitted if magic_end_index < 0

        # Emit magic comment lines
        (0..magic_end_index).each do |idx|
          comment = leading_comments[idx]
          line_num = comment.location.start_line
          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          # Emit gap lines between consecutive magic comments
          if last_emitted > 0 && line_num > last_emitted + 1
            ((last_emitted + 1)...line_num).each do |gap_num|
              gap = analysis.line_at(gap_num)&.chomp || ""
              result.add_line(gap, decision: MergeResult::DECISION_KEPT_DEST, dest_line: gap_num)
              @dest_prefix_comment_lines << gap_num
            end
          end

          result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
          @dest_prefix_comment_lines << line_num
          last_emitted = line_num
        end

        # Emit blank lines between last magic comment and next content
        next_content_line = if magic_end_index + 1 < leading_comments.size
          leading_comments[magic_end_index + 1].location.start_line
        else
          first_node.location.start_line
        end

        if next_content_line > last_emitted + 1
          ((last_emitted + 1)...next_content_line).each do |gap_num|
            gap_line = analysis.line_at(gap_num)&.chomp || ""
            next unless gap_line.strip.empty?

            result.add_line(gap_line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: gap_num)
            @dest_prefix_comment_lines << gap_num
            last_emitted = gap_num
          end
        end

        last_emitted
      end

      # Check if a Prism comment object is a Ruby magic comment.
      #
      # @param comment [Prism::Comment] A Prism comment object
      # @return [Boolean]
      def prism_magic_comment?(comment)
        text = comment.slice.sub(/\A#\s*/, "").strip
        Comment::Line::MAGIC_COMMENT_PATTERNS.any? { |_, pat| text.match?(pat) }
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

      def add_matched_template_node_to_result(result, template_node, dest_node)
        decision = MergeResult::DECISION_KEPT_TEMPLATE
        last_emitted_dest_line = nil

        template_leading = filtered_leading_comments_for(template_node, :template)
        dest_leading = filtered_leading_comments_for(dest_node, :destination)

        leading_comments = template_leading[:comments]
        leading_analysis = @template_analysis
        prev_comment_line = template_leading[:last_skipped_line]

        if leading_comments.empty? && dest_leading[:comments].any?
          leading_comments = dest_leading[:comments]
          leading_analysis = @dest_analysis
          prev_comment_line = nil
        end

        emit_leading_comments(
          result,
          leading_comments,
          analysis: leading_analysis,
          source: leading_analysis.equal?(@template_analysis) ? :template : :destination,
          decision: decision,
          prev_comment_line: prev_comment_line,
        )

        if leading_analysis.equal?(@dest_analysis) && leading_comments.any?
          last_emitted_dest_line = leading_comments.last.location.start_line
        end

        if leading_comments.any?
          emitted_gap_line = emit_blank_lines_between(
            result,
            last_comment_line: leading_comments.last.location.start_line,
            next_content_line: leading_analysis.equal?(@template_analysis) ? template_node.location.start_line : dest_node.location.start_line,
            analysis: leading_analysis,
            source: leading_analysis.equal?(@template_analysis) ? :template : :destination,
            decision: decision,
          )
          last_emitted_dest_line = emitted_gap_line if leading_analysis.equal?(@dest_analysis) && emitted_gap_line
        end

        template_inline_entries = @template_analysis.send(:owner_inline_comment_entries, template_node)
        dest_inline_entries = @dest_analysis.send(:owner_inline_comment_entries, dest_node)
        inline_entries = template_inline_entries.any? ? template_inline_entries : dest_inline_entries

        (template_node.location.start_line..template_node.location.end_line).each do |line_num|
          line = @template_analysis.line_at(line_num)&.chomp || ""

          if line_num == template_node.location.end_line && template_inline_entries.empty? && inline_entries.any?
            line = append_inline_comment_entries(line, inline_entries)
          end

          result.add_line(line, decision: decision, template_line: line_num)
        end

        template_trailing_comments = external_trailing_comments_for(template_node)
        dest_trailing_comments = external_trailing_comments_for(dest_node)
        trailing_comments = template_trailing_comments.any? ? template_trailing_comments : dest_trailing_comments
        trailing_analysis = template_trailing_comments.any? ? @template_analysis : @dest_analysis
        trailing_source = trailing_analysis.equal?(@template_analysis) ? :template : :destination
        trailing_node = trailing_analysis.equal?(@template_analysis) ? template_node : dest_node

        if trailing_comments.any?
          emitted_dest_line = emit_external_trailing_comments(
            result,
            trailing_comments,
            source_node: trailing_node,
            analysis: trailing_analysis,
            source: trailing_source,
            decision: decision,
          )
          last_emitted_dest_line = emitted_dest_line if trailing_analysis.equal?(@dest_analysis) && emitted_dest_line
          return {last_emitted_dest_line: last_emitted_dest_line}
        end

        trailing_line = template_node.location.end_line + 1
        trailing_content = @template_analysis.line_at(trailing_line)
        if trailing_content && trailing_content.strip.empty?
          result.add_line("", decision: decision, template_line: trailing_line)
        end

        {last_emitted_dest_line: last_emitted_dest_line}
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

        # Get leading comments attached to the node, skipping any that were
        # already emitted by emit_dest_prefix_lines (dest magic comments at
        # the top of the file). Non-top-of-file magic comments are left alone
        # — they may be documentation or intentional repetition.
        #
        # For dest nodes: skip by exact line number match.
        # For template nodes: skip magic comments if dest prefix already
        # emitted magic comments (to avoid duplication).
        leading = filtered_leading_comments_for(node, source)
        leading_comments = leading[:comments]

        emit_leading_comments(
          result,
          leading_comments,
          analysis: analysis,
          source: source,
          decision: decision,
          prev_comment_line: source == :template ? leading[:last_skipped_line] : nil,
        )

        # Add blank line before node if there's a gap after comments
        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          if node.location.start_line > last_comment_line + 1
            # There's a gap - add blank lines
            ((last_comment_line + 1)...node.location.start_line).each do |line_num|
              # Skip lines already emitted by emit_dest_prefix_lines
              next if @dest_prefix_comment_lines&.include?(line_num)

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

        # Add trailing comments attached to the node (e.g., end-of-file comments).
        # Skip comments on the same line as the node — inline comments are already
        # included when we output the node's source lines via analysis.line_at.
        trailing_comments = node.location.respond_to?(:trailing_comments) ? node.location.trailing_comments : []
        node_line_range = node.location.start_line..node.location.end_line
        trailing_comments.each do |comment|
          line_num = comment.location.start_line
          next if node_line_range.cover?(line_num)

          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end
        end
      end

      def filtered_leading_comments_for(node, source)
        all_leading_comments = node.location.respond_to?(:leading_comments) ? node.location.leading_comments : []
        last_skipped_line = nil

        comments = if source == :destination
          all_leading_comments.reject do |comment|
            if @dest_prefix_comment_lines&.include?(comment.location.start_line)
              last_skipped_line = comment.location.start_line
              true
            end
          end
        elsif @dest_prefix_comment_lines&.any?
          all_leading_comments.reject do |comment|
            if prism_magic_comment?(comment)
              last_skipped_line = comment.location.start_line
              true
            end
          end
        else
          all_leading_comments
        end

        {comments: comments, last_skipped_line: last_skipped_line}
      end

      def emit_leading_comments(result, comments, analysis:, source:, decision:, prev_comment_line: nil)
        comments.each do |comment|
          line_num = comment.location.start_line

          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              next if @dest_prefix_comment_lines&.include?(blank_line_num)

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
      end

      def emit_blank_lines_between(result, last_comment_line:, next_content_line:, analysis:, source:, decision:)
        return if next_content_line <= last_comment_line + 1

        last_emitted_line = nil

        ((last_comment_line + 1)...next_content_line).each do |line_num|
          next if @dest_prefix_comment_lines&.include?(line_num)

          line = analysis.line_at(line_num)&.chomp || ""
          next unless line.strip.empty?

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end

          last_emitted_line = line_num
        end

        last_emitted_line
      end

      def emit_external_trailing_comments(result, comments, source_node:, analysis:, source:, decision:)
        previous_line = source_node.location.end_line
        last_emitted_line = nil

        comments.each do |comment|
          line_num = comment.location.start_line
          gap_line = emit_blank_lines_between(
            result,
            last_comment_line: previous_line,
            next_content_line: line_num,
            analysis: analysis,
            source: source,
            decision: decision,
          )
          last_emitted_line = gap_line if gap_line

          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip
          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end

          previous_line = line_num
          last_emitted_line = line_num
        end

        last_emitted_line
      end

      def append_inline_comment_entries(line, entries)
        suffix = entries.map { |entry| entry[:raw].strip }.join(" ")
        return line if suffix.empty?

        [line.rstrip, suffix].reject(&:empty?).join(" ")
      end

      def inline_comment_entries_by_line(entries)
        entries.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |entry, by_line|
          by_line[entry[:line]] << entry
        end
      end

      def line_inline_comment_entries(analysis, line_num)
        line = analysis.line_at(line_num).to_s
        return [] if line.strip.empty? || line.lstrip.start_with?("#")
        return [] unless analysis.respond_to?(:parse_result) && analysis.parse_result.respond_to?(:comments)

        Array(analysis.parse_result.comments).filter_map do |comment|
          next unless comment.location.start_line == line_num

          {line: line_num, raw: comment.slice.chomp}
        end
      end

      def begin_node_boundary_lines(node)
        return [node.location.start_line, node.location.end_line].uniq unless node.is_a?(Prism::BeginNode)

        [
          node.location.start_line,
          node.rescue_clause&.location&.start_line,
          node.else_clause&.location&.start_line,
          node.ensure_clause&.location&.start_line,
          node.location.end_line,
        ].compact.uniq
      end

      def wrapper_inline_comment_entries_by_line(analysis, node)
        owner_entries = analysis.send(:owner_inline_comment_entries, node)
        wrapper_lines = begin_node_boundary_lines(node)
        raw_entries = wrapper_lines.flat_map { |line_num| line_inline_comment_entries(analysis, line_num) }
        inline_comment_entries_by_line((owner_entries + raw_entries).uniq { |entry| [entry[:line], entry[:raw]] })
      end

      def begin_node_clause_start_line(node)
        return unless node.is_a?(Prism::BeginNode)

        [
          node.rescue_clause&.location&.start_line,
          node.else_clause&.location&.start_line,
          node.ensure_clause&.location&.start_line,
        ].compact.min
      end

      def begin_node_rescue_nodes(node)
        return [] unless node.is_a?(Prism::BeginNode)

        rescue_nodes = []
        current = node.rescue_clause
        while current.is_a?(Prism::RescueNode)
          rescue_nodes << current
          current = if current.respond_to?(:subsequent)
            current.subsequent
          else
            current.consequent
          end
        end
        rescue_nodes
      end

      def rescue_node_signature(rescue_node)
        exceptions = Array(rescue_node.exceptions).map do |exception_node|
          exception_node.respond_to?(:slice) ? exception_node.slice : exception_node.to_s
        end
        normalized_exceptions = exceptions.map { |exception| exception.to_s.sub(/\A::/, "") }
        exceptions = if normalized_exceptions.empty? || normalized_exceptions == ["StandardError"]
          [:standard_error]
        else
          normalized_exceptions.sort
        end
        exceptions
      end

      def rescue_node_reference_name(rescue_node)
        return unless rescue_node.is_a?(Prism::RescueNode)

        reference = rescue_node.reference if rescue_node.respond_to?(:reference)
        return unless reference

        return reference.slice if reference.respond_to?(:slice)
        return reference.name.to_s if reference.respond_to?(:name)

        reference.to_s
      end

      def local_variable_read_names_in(node, names = [])
        return names unless node

        if node.is_a?(Prism::LocalVariableReadNode)
          names << node.name.to_s
        elsif node.is_a?(Prism::CallNode) && node.respond_to?(:variable_call?) && node.variable_call?
          names << node.name.to_s
        end
        node.compact_child_nodes.each { |child| local_variable_read_names_in(child, names) } if node.respond_to?(:compact_child_nodes)
        names
      end

      def local_variable_read_names_in_source(source)
        return [] if source.to_s.strip.empty?

        parse_result = Prism.parse(source)
        return [] unless parse_result.success?

        local_variable_read_names_in(parse_result.value).uniq
      end

      def local_reference_node_named?(node, name)
        return false unless node && name

        if node.is_a?(Prism::LocalVariableReadNode)
          node.name.to_s == name
        elsif node.is_a?(Prism::CallNode) && node.respond_to?(:variable_call?) && node.variable_call?
          node.name.to_s == name
        else
          false
        end
      end

      def local_reference_offsets_in(node, name, offsets = [])
        return offsets unless node

        if local_reference_node_named?(node, name) && node.respond_to?(:location) && node.location
          offsets << [node.location.start_offset, node.location.length]
        end

        node.compact_child_nodes.each { |child| local_reference_offsets_in(child, name, offsets) } if node.respond_to?(:compact_child_nodes)
        offsets
      end

      def rewrite_local_reference_in_source(source, from:, to:)
        return source if from.nil? || to.nil? || from == to || source.to_s.empty?

        parse_result = Prism.parse(source)
        return source unless parse_result.success?

        offsets = local_reference_offsets_in(parse_result.value, from)
        return source if offsets.empty?

        rewritten = source.dup
        offsets.sort_by(&:first).reverse_each do |start_offset, length|
          rewritten[start_offset, length] = to
        end
        rewritten
      end

      def normalized_clause_body_and_header_source(template_clause_node, dest_clause_node, clause_body, preferred_source)
        return {header_source: preferred_source, clause_body: clause_body} unless template_clause_node.is_a?(Prism::RescueNode) && dest_clause_node.is_a?(Prism::RescueNode)

        template_reference = rescue_node_reference_name(template_clause_node)
        dest_reference = rescue_node_reference_name(dest_clause_node)
        return {header_source: preferred_source, clause_body: clause_body} if template_reference == dest_reference

        merged_references = local_variable_read_names_in_source(clause_body)
        needs_template_reference = template_reference && merged_references.include?(template_reference)
        needs_dest_reference = dest_reference && merged_references.include?(dest_reference)

        header_source = if needs_dest_reference && !needs_template_reference
          :destination
        elsif needs_template_reference && !needs_dest_reference
          :template
        else
          preferred_source
        end

        chosen_reference = header_source == :template ? template_reference : dest_reference
        alternate_reference = header_source == :template ? dest_reference : template_reference
        normalized_body = if chosen_reference && alternate_reference && merged_references.include?(alternate_reference)
          rewrite_local_reference_in_source(clause_body, from: alternate_reference, to: chosen_reference)
        else
          clause_body
        end

        {header_source: header_source, clause_body: normalized_body}
      end

      def begin_node_clause_regions(node)
        return [] unless node.is_a?(Prism::BeginNode)

        rescue_nodes = begin_node_rescue_nodes(node)
        rescue_occurrences = Hash.new(0)
        region_defs = rescue_nodes.map do |rescue_node|
          signature = rescue_node_signature(rescue_node)
          occurrence = rescue_occurrences[signature]
          rescue_occurrences[signature] += 1
          {type: [:rescue_clause, signature, occurrence], start_line: rescue_node.location.start_line}
        end
        if node.else_clause&.location
          region_defs << {type: :else_clause, start_line: node.else_clause.location.start_line}
        end
        if node.ensure_clause&.location
          region_defs << {type: :ensure_clause, start_line: node.ensure_clause.location.start_line}
        end

        region_defs.each_with_index.map do |region_def, index|
          next_start_line = region_defs[index + 1]&.dig(:start_line)
          {
            type: region_def[:type],
            start_line: region_def[:start_line],
            end_line: (next_start_line ? next_start_line - 1 : node.location.end_line - 1),
          }
        end
      end

      def begin_node_clause_nodes_by_type(node)
        return {} unless node.is_a?(Prism::BeginNode)

        rescue_occurrences = Hash.new(0)
        clause_nodes = {}
        begin_node_rescue_nodes(node).each do |rescue_node|
          signature = rescue_node_signature(rescue_node)
          occurrence = rescue_occurrences[signature]
          rescue_occurrences[signature] += 1
          clause_nodes[[:rescue_clause, signature, occurrence]] = rescue_node
        end
        clause_nodes[:else_clause] = node.else_clause if node.else_clause
        clause_nodes[:ensure_clause] = node.ensure_clause if node.ensure_clause
        clause_nodes
      end

      def clause_statements_node(node)
        case node
        when Prism::RescueNode, Prism::ElseNode, Prism::EnsureNode
          node.statements
        end
      end

      def clause_header_end_line(node, region)
        return region[:start_line] unless node && region

        header_lines = []
        header_lines << node.keyword_loc.end_line if node.respond_to?(:keyword_loc) && node.keyword_loc

        if node.is_a?(Prism::RescueNode)
          header_lines.concat(Array(node.exceptions).filter_map { |exception_node| exception_node.location.end_line if exception_node.respond_to?(:location) && exception_node.location })
          header_lines << node.operator_loc.end_line if node.respond_to?(:operator_loc) && node.operator_loc
          header_lines << node.reference.location.end_line if node.respond_to?(:reference) && node.reference&.respond_to?(:location) && node.reference.location
        end

        header_lines.compact.max || region[:start_line]
      end

      def clause_body_start_line(node, region)
        clause_header_end_line(node, region) + 1
      end

      def extract_region_body(region, analysis, body_start_line: region[:start_line] + 1, body_end_line: region[:end_line])
        return "" unless region

        return "" if body_end_line < body_start_line

        lines = []
        (body_start_line..body_end_line).each do |line_num|
          lines << analysis.line_at(line_num).chomp
        end
        lines.join("\n") + "\n"
      end

      def emit_clause_header_lines(
        template_clause_node,
        template_region,
        dest_clause_node,
        dest_region,
        header_source,
        decision,
        template_inline_by_line,
        dest_inline_by_line
      )
        header_node = header_source == :template ? template_clause_node : dest_clause_node
        header_region = header_source == :template ? template_region : dest_region
        header_analysis = header_source == :template ? @template_analysis : @dest_analysis
        header_end_line = clause_header_end_line(header_node, header_region)
        template_header_end_line = clause_header_end_line(template_clause_node, template_region)
        dest_header_end_line = clause_header_end_line(dest_clause_node, dest_region)

        (header_region[:start_line]..header_end_line).each do |line_num|
          line = header_analysis.line_at(line_num)&.chomp || ""

          if header_source == :template &&
              line_num == template_header_end_line &&
              template_inline_by_line[line_num].empty?
            dest_clause_inline = dest_inline_by_line[dest_header_end_line]
            line = append_inline_comment_entries(line, dest_clause_inline) if dest_clause_inline.any?
          end

          @result.add_line(
            line,
            decision: decision,
            template_line: header_source == :template ? line_num : nil,
            dest_line: header_source == :destination ? line_num : nil,
          )
        end
      end

      def split_leading_comment_prefix(body_text)
        lines = body_text.lines
        prefix_lines = []
        index = 0

        while index < lines.length
          line = lines[index]
          stripped = line.strip
          break unless stripped.empty? || line.lstrip.start_with?("#")

          prefix_lines << line
          index += 1
        end

        [prefix_lines.join, lines[index..]&.join.to_s]
      end

      def body_contains_freeze_markers?(body_text)
        return false unless @freeze_token && !@freeze_token.empty?

        body_text.match?(/^\s*#\s*#{Regexp.escape(@freeze_token)}:(?:freeze|unfreeze)\b/)
      end

      def clause_body_components(node, region, analysis)
        return {merge_body: "", trailing_suffix: ""} unless node && region

        statements_node = clause_statements_node(node)
        return {merge_body: "", trailing_suffix: ""} unless statements_node&.is_a?(Prism::StatementsNode)

        body_statements = statements_node.body
        body_start_line = clause_body_start_line(node, region)
        return {
          merge_body: "",
          trailing_suffix: extract_region_body(region, analysis, body_start_line: body_start_line),
        } if body_statements.empty?

        last_statement_end_line = body_statements.last.location.end_line
        {
          merge_body: extract_region_body(region, analysis, body_start_line: body_start_line, body_end_line: last_statement_end_line),
          trailing_suffix: if region[:end_line] > last_statement_end_line
            lines = []
            ((last_statement_end_line + 1)..region[:end_line]).each do |line_num|
              lines << analysis.line_at(line_num).chomp
            end
            lines.join("\n") + "\n"
          else
            ""
          end,
        }
      end

      def statement_signatures_for_nodes(nodes, analysis)
        Set.new(
          Array(nodes).filter_map do |node|
            signature = analysis.generate_signature(node)
            signature if signature
          end,
        )
      end

      def begin_node_statement_signatures(node, analysis)
        return Set.new unless node.is_a?(Prism::BeginNode)

        signatures = statement_signatures_for_nodes(node.statements&.body, analysis)
        begin_node_clause_nodes_by_type(node).each_value do |clause_node|
          signatures.merge(statement_signatures_for_nodes(clause_statements_node(clause_node)&.body, analysis))
        end
        signatures
      end

      def clause_body_fully_duplicated_in_preferred_begin?(clause_node, clause_analysis, preferred_begin_node, preferred_begin_analysis)
        clause_statements = Array(clause_statements_node(clause_node)&.body)
        return false if clause_statements.empty?

        clause_signatures = clause_statements.map { |statement| clause_analysis.generate_signature(statement) }
        return false if clause_signatures.any?(&:nil?)

        preferred_signatures = begin_node_statement_signatures(preferred_begin_node, preferred_begin_analysis)
        clause_signatures.all? { |signature| preferred_signatures.include?(signature) }
      end

      def merge_clause_body_recursively(template_clause_node, template_clause_region, dest_clause_node, dest_clause_region)
        template_components = clause_body_components(template_clause_node, template_clause_region, @template_analysis)
        dest_components = clause_body_components(dest_clause_node, dest_clause_region, @dest_analysis)
        template_body = template_components[:merge_body]
        dest_body = dest_components[:merge_body]

        return unless clause_bodies_have_matching_statements?(template_body, dest_body)

        body_merger = SmartMerger.new(
          template_body,
          dest_body,
          signature_generator: @raw_signature_generator,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          freeze_token: @freeze_token,
          max_recursion_depth: @max_recursion_depth,
          current_depth: @current_depth + 1,
          node_typing: @node_typing,
        )
        {
          merged_body: body_merger.merge.rstrip,
          template_trailing_suffix: template_components[:trailing_suffix],
          dest_trailing_suffix: dest_components[:trailing_suffix],
        }
      end

      def clause_bodies_have_matching_statements?(template_body, dest_body)
        return false if template_body.strip.empty? || dest_body.strip.empty?

        effective_signature_generator = build_effective_signature_generator(@raw_signature_generator, @node_typing)
        template_analysis = FileAnalysis.new(
          template_body,
          freeze_token: @freeze_token,
          signature_generator: effective_signature_generator,
        )
        dest_analysis = FileAnalysis.new(
          dest_body,
          freeze_token: @freeze_token,
          signature_generator: effective_signature_generator,
        )

        !(build_signature_map(template_analysis).keys & build_signature_map(dest_analysis).keys).empty?
      end

      def merge_ordered_clause_types(primary_types, secondary_types)
        ordered = primary_types.dup

        secondary_types.each_with_index do |clause_type, secondary_index|
          next if ordered.include?(clause_type)

          previous_shared = secondary_types[0...secondary_index].reverse.find { |type| ordered.include?(type) }
          next_shared = secondary_types[(secondary_index + 1)..]&.find { |type| ordered.include?(type) }

          if previous_shared
            insert_at = ordered.index(previous_shared) + 1
            ordered.insert(insert_at, clause_type)
          elsif next_shared
            insert_at = ordered.index(next_shared)
            ordered.insert(insert_at, clause_type)
          else
            ordered << clause_type
          end
        end

        ordered
      end

      def rescue_clause_type?(clause_type)
        clause_type.is_a?(Array) && clause_type.first == :rescue_clause
      end

      def broad_rescue_clause_type?(clause_type)
        rescue_clause_type?(clause_type) && clause_type[1] == [:standard_error]
      end

      def clause_kind_sort_key(clause_type)
        return 0 if rescue_clause_type?(clause_type)
        return 1 if clause_type == :else_clause
        return 2 if clause_type == :ensure_clause

        3
      end

      def normalize_exception_name(exception_name)
        return "StandardError" if exception_name == :standard_error

        name = exception_name.to_s.sub(/\A::/, "")
        name.empty? ? nil : name
      end

      def qualify_source_constant_name(constant_name, namespace = nil)
        normalized_name = normalize_exception_name(constant_name)
        return if normalized_name.nil?
        return normalized_name if constant_name.to_s.start_with?("::") || namespace.nil? || namespace.empty?

        "#{namespace}::#{normalized_name}"
      end

      def source_defined_exception_hierarchy
        @source_defined_exception_hierarchy ||= begin
          definitions = []
          [@template_analysis, @dest_analysis].compact.each do |analysis|
            next unless analysis.respond_to?(:parse_result) && analysis.parse_result&.respond_to?(:value)

            collect_source_defined_exception_definitions(analysis.parse_result.value, nil, definitions)
          end

          defined_names = definitions.map { |definition| definition[:name] }.compact.to_set
          definitions.each_with_object({}) do |definition, hierarchy|
            next unless definition[:name] && definition[:superclass]

            superclass_name = if definition[:superclass].to_s.start_with?("::")
              normalize_exception_name(definition[:superclass])
            else
              candidate_name = qualify_source_constant_name(definition[:superclass], definition[:namespace])
              defined_names.include?(candidate_name) ? candidate_name : normalize_exception_name(definition[:superclass])
            end

            hierarchy[definition[:name]] ||= superclass_name if superclass_name
          end
        end
      end

      def collect_source_defined_exception_definitions(node, namespace, definitions)
        return unless node

        case node
        when Prism::ProgramNode
          collect_source_defined_exception_definitions(node.statements, namespace, definitions)
        when Prism::StatementsNode
          node.body.each { |child| collect_source_defined_exception_definitions(child, namespace, definitions) }
        when Prism::ModuleNode
          module_name = qualify_source_constant_name(node.constant_path.slice, namespace)
          collect_source_defined_exception_definitions(node.body, module_name, definitions)
        when Prism::ClassNode
          class_name = qualify_source_constant_name(node.constant_path.slice, namespace)
          definitions << {
            name: class_name,
            namespace: namespace,
            superclass: node.superclass&.slice,
          }
          collect_source_defined_exception_definitions(node.body, class_name, definitions)
        else
          node.compact_child_nodes.each { |child| collect_source_defined_exception_definitions(child, namespace, definitions) } if node.respond_to?(:compact_child_nodes)
        end
      end

      def resolve_exception_constant(exception_name)
        return ::StandardError if exception_name == :standard_error
        return unless exception_name.is_a?(String) && !exception_name.empty?

        exception_name.split("::").reject(&:empty?).inject(Object) { |scope, const_name| scope.const_get(const_name) }
      rescue NameError
        nil
      end

      def rescue_clause_exception_constants(clause_type)
        return [] unless rescue_clause_type?(clause_type)

        Array(clause_type[1]).filter_map { |exception_name| resolve_exception_constant(exception_name) }
      end

      def rescue_clause_exception_names(clause_type)
        return [] unless rescue_clause_type?(clause_type)

        Array(clause_type[1]).filter_map { |exception_name| normalize_exception_name(exception_name) }
      end

      def exception_constant_covers?(covering_constant, covered_constant)
        return true if covering_constant == covered_constant

        covered_constant < covering_constant
      rescue StandardError
        false
      end

      def source_defined_exception_covers?(covering_name, covered_name)
        normalized_covering = normalize_exception_name(covering_name)
        current_name = normalize_exception_name(covered_name)
        return false if normalized_covering.nil? || current_name.nil?
        return true if normalized_covering == current_name

        while (current_name = source_defined_exception_hierarchy[current_name])
          return true if current_name == normalized_covering
        end

        false
      end

      def exception_name_covers?(covering_name, covered_name)
        covering_constant = resolve_exception_constant(covering_name)
        covered_constant = resolve_exception_constant(covered_name)

        if covering_constant && covered_constant
          exception_constant_covers?(covering_constant, covered_constant)
        else
          source_defined_exception_covers?(covering_name, covered_name)
        end
      end

      def rescue_clause_covers?(covering_clause_type, covered_clause_type)
        return false unless rescue_clause_type?(covering_clause_type) && rescue_clause_type?(covered_clause_type)

        covering_names = rescue_clause_exception_names(covering_clause_type)
        covered_names = rescue_clause_exception_names(covered_clause_type)
        return false if covering_names.empty? || covered_names.empty?

        covered_names.all? do |covered_name|
          covering_names.any? do |covering_name|
            exception_name_covers?(covering_name, covered_name)
          end
        end
      end

      def broader_rescue_clause_type_than?(left_clause_type, right_clause_type)
        return false unless rescue_clause_type?(left_clause_type) && rescue_clause_type?(right_clause_type)

        rescue_clause_covers?(left_clause_type, right_clause_type) &&
          !rescue_clause_covers?(right_clause_type, left_clause_type)
      end

      def canonicalize_rescue_clause_order(clause_types)
        rescue_clause_types = clause_types.select { |clause_type| rescue_clause_type?(clause_type) }
        return clause_types if rescue_clause_types.length < 2
        ordered_rescue_types = rescue_clause_types.dup

        if rescue_clause_types.any? { |clause_type| broad_rescue_clause_type?(clause_type) } &&
            rescue_clause_types.any? { |clause_type| !broad_rescue_clause_type?(clause_type) }
          specific_rescue_types = ordered_rescue_types.reject { |clause_type| broad_rescue_clause_type?(clause_type) }
          broad_rescue_types = ordered_rescue_types.select { |clause_type| broad_rescue_clause_type?(clause_type) }
          ordered_rescue_types = specific_rescue_types + broad_rescue_types
        end

        loop do
          swapped = false

          (0...(ordered_rescue_types.length - 1)).each do |index|
            left_clause_type = ordered_rescue_types[index]
            right_clause_type = ordered_rescue_types[index + 1]
            next unless broader_rescue_clause_type_than?(left_clause_type, right_clause_type)

            ordered_rescue_types[index], ordered_rescue_types[index + 1] = right_clause_type, left_clause_type
            swapped = true
          end

          break unless swapped
        end

        clause_types.map do |clause_type|
          rescue_clause_type?(clause_type) ? ordered_rescue_types.shift : clause_type
        end
      end

      def canonicalize_begin_clause_kind_order(clause_types)
        clause_types.each_with_index
          .sort_by { |(clause_type, index)| [clause_kind_sort_key(clause_type), index] }
          .map(&:first)
      end

      def begin_node_has_clause_or_body?(node)
        return false unless node.is_a?(Prism::BeginNode)

        node.statements || node.rescue_clause || node.else_clause || node.ensure_clause
      end

      def begin_node_clause_line_map(template_node, dest_node)
        return {} unless template_node.is_a?(Prism::BeginNode) && dest_node.is_a?(Prism::BeginNode)

        template_regions = begin_node_clause_regions(template_node).each_with_object({}) do |region, regions_by_type|
          regions_by_type[region[:type]] = region
        end
        dest_regions = begin_node_clause_regions(dest_node).each_with_object({}) do |region, regions_by_type|
          regions_by_type[region[:type]] = region
        end

        template_regions.each_with_object({}) do |(type, region), mapping|
          dest_region = dest_regions[type]
          next unless dest_region

          mapping[region[:start_line]] = dest_region[:start_line]
        end
      end

      def external_trailing_comments_for(node)
        trailing_comments = node.location.respond_to?(:trailing_comments) ? node.location.trailing_comments : []
        node_line_range = node.location.start_line..node.location.end_line
        trailing_comments.reject { |comment| node_line_range.cover?(comment.location.start_line) }
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
          # begin/rescue/ensure blocks - recurse even for clause-only wrappers
          # so rescue/else/ensure merging still runs when the main begin body is empty.
          !!(begin_node_has_clause_or_body?(actual_template) && begin_node_has_clause_or_body?(actual_dest))
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

        # Recursively merge the bodies with incremented depth.
        # Use the raw (unwrapped) signature_generator so the inner SmartMerger
        # can wrap it fresh via build_effective_signature_generator. Using the
        # already-effective generator would cause double-wrapping when
        # node_typing is also passed, making is_a? checks fail.
        body_merger = SmartMerger.new(
          template_body,
          dest_body,
          signature_generator: @raw_signature_generator,
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
        last_emitted_dest_line = nil

        # Determine which comments to use (skipping any already emitted
        # by emit_dest_prefix_lines):
        # - If template preference and template has comments, use template's
        # - If template preference but template has NO comments, preserve dest's comments
        # - If dest preference, use dest's comments
        template_comments = actual_template.location.respond_to?(:leading_comments) ? actual_template.location.leading_comments : []
        dest_comments = actual_dest.location.respond_to?(:leading_comments) ? actual_dest.location.leading_comments : []
        dest_comments = dest_comments.reject { |c| @dest_prefix_comment_lines&.include?(c.location.start_line) }
        last_skipped_template_line = nil
        if @dest_prefix_comment_lines&.any?
          template_comments = template_comments.reject do |c|
            if prism_magic_comment?(c)
              last_skipped_template_line = c.location.start_line
              true
            end
          end
        end

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
        template_inline_by_line = wrapper_inline_comment_entries_by_line(@template_analysis, actual_template)
        dest_inline_by_line = wrapper_inline_comment_entries_by_line(@dest_analysis, actual_dest)
        begin_clause_line_map = begin_node_clause_line_map(actual_template, actual_dest)

        # Add leading comments with blank lines between them preserved.
        # Seed prev_comment_line for template source so gap lines between
        # stripped magic comments and remaining comments are preserved.
        prev_comment_line = (comment_source == :template) ? last_skipped_template_line : nil
        leading_comments.each do |comment|
          line_num = comment.location.start_line

          # Add blank lines between this comment and the previous one
          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              # Skip lines already emitted by emit_dest_prefix_lines
              next if @dest_prefix_comment_lines&.include?(blank_line_num)

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
        if node_preference == :template && template_inline_by_line[actual_template.location.start_line].empty?
          dest_opening_inline = dest_inline_by_line[actual_dest.location.start_line]
          opening_line = append_inline_comment_entries(opening_line.to_s.chomp, dest_opening_inline) if dest_opening_inline.any?
        end
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

        template_clause_regions = begin_node_clause_regions(actual_template).each_with_object({}) do |region, regions_by_type|
          regions_by_type[region[:type]] = region
        end
        dest_clause_regions = begin_node_clause_regions(actual_dest).each_with_object({}) do |region, regions_by_type|
          regions_by_type[region[:type]] = region
        end
        template_clause_nodes = begin_node_clause_nodes_by_type(actual_template)
        dest_clause_nodes = begin_node_clause_nodes_by_type(actual_dest)
        if template_clause_regions.any? || dest_clause_regions.any?
          clause_types = if node_preference == :template
            merge_ordered_clause_types(template_clause_regions.keys, dest_clause_regions.keys)
          else
            merge_ordered_clause_types(dest_clause_regions.keys, template_clause_regions.keys)
          end
          clause_types = canonicalize_rescue_clause_order(clause_types)
          clause_types = canonicalize_begin_clause_kind_order(clause_types)
          clause_types.each do |clause_type|
            template_region = template_clause_regions[clause_type]
            dest_region = dest_clause_regions[clause_type]
            template_clause_node = template_clause_nodes[clause_type]
            dest_clause_node = dest_clause_nodes[clause_type]

            if template_region && dest_region && template_clause_node && dest_clause_node
              merged_clause_body = merge_clause_body_recursively(template_clause_node, template_region, dest_clause_node, dest_region)
              if merged_clause_body
                normalized_clause = normalized_clause_body_and_header_source(
                  template_clause_node,
                  dest_clause_node,
                  merged_clause_body[:merged_body],
                  node_preference,
                )
                header_source = normalized_clause[:header_source]
                emit_clause_header_lines(
                  template_clause_node,
                  template_region,
                  dest_clause_node,
                  dest_region,
                  header_source,
                  decision,
                  template_inline_by_line,
                  dest_inline_by_line,
                )

                normalized_clause[:clause_body].lines.each do |line|
                  @result.add_line(
                    line.chomp,
                    decision: decision,
                    template_line: nil,
                    dest_line: nil,
                  )
                end

                trailing_suffix = if node_preference == :template
                  merged_clause_body[:template_trailing_suffix].empty? ? merged_clause_body[:dest_trailing_suffix] : merged_clause_body[:template_trailing_suffix]
                else
                  merged_clause_body[:dest_trailing_suffix].empty? ? merged_clause_body[:template_trailing_suffix] : merged_clause_body[:dest_trailing_suffix]
                end
                trailing_suffix.lines.each do |line|
                  @result.add_line(
                    line.chomp,
                    decision: decision,
                    template_line: nil,
                    dest_line: nil,
                  )
                end
                next
              end

              preferred_clause_node = node_preference == :template ? template_clause_node : dest_clause_node
              preferred_clause_region = node_preference == :template ? template_region : dest_region
              preferred_clause_analysis = node_preference == :template ? @template_analysis : @dest_analysis
              alternate_clause_node = node_preference == :template ? dest_clause_node : template_clause_node
              alternate_clause_region = node_preference == :template ? dest_region : template_region
              alternate_clause_analysis = node_preference == :template ? @dest_analysis : @template_analysis

              preferred_components = clause_body_components(preferred_clause_node, preferred_clause_region, preferred_clause_analysis)
              alternate_components = clause_body_components(alternate_clause_node, alternate_clause_region, alternate_clause_analysis)
              if !body_contains_freeze_markers?(preferred_components[:merge_body] + preferred_components[:trailing_suffix]) &&
                  body_contains_freeze_markers?(alternate_components[:merge_body] + alternate_components[:trailing_suffix])
                body_to_emit = alternate_components[:merge_body]
                trailing_suffix = alternate_components[:trailing_suffix]
              else
              preferred_prefix, preferred_remainder = split_leading_comment_prefix(preferred_components[:merge_body])
              alternate_prefix, = split_leading_comment_prefix(alternate_components[:merge_body])
              body_to_emit = preferred_prefix.empty? && !alternate_prefix.empty? ? (alternate_prefix + preferred_remainder) : preferred_components[:merge_body]
              trailing_suffix = preferred_components[:trailing_suffix].empty? ? alternate_components[:trailing_suffix] : preferred_components[:trailing_suffix]
              end

              normalized_clause = normalized_clause_body_and_header_source(
                template_clause_node,
                dest_clause_node,
                body_to_emit,
                node_preference,
              )
              body_to_emit = normalized_clause[:clause_body]
              header_source = normalized_clause[:header_source]
              emit_clause_header_lines(
                template_clause_node,
                template_region,
                dest_clause_node,
                dest_region,
                header_source,
                decision,
                template_inline_by_line,
                dest_inline_by_line,
              )

              body_to_emit.lines.each do |line|
                @result.add_line(
                  line.chomp,
                  decision: decision,
                  template_line: nil,
                  dest_line: nil,
                )
              end
              trailing_suffix.lines.each do |line|
                @result.add_line(
                  line.chomp,
                  decision: decision,
                  template_line: nil,
                  dest_line: nil,
                )
              end
              next
            end

            region, region_analysis = if node_preference == :template
              template_region ? [template_region, @template_analysis] : (dest_region ? [dest_region, @dest_analysis] : nil)
            else
              dest_region ? [dest_region, @dest_analysis] : (template_region ? [template_region, @template_analysis] : nil)
            end
            next unless region

            if (node_preference == :template && !template_region && dest_clause_node &&
                clause_body_fully_duplicated_in_preferred_begin?(dest_clause_node, @dest_analysis, actual_template, @template_analysis)) ||
                (node_preference == :destination && !dest_region && template_clause_node &&
                clause_body_fully_duplicated_in_preferred_begin?(template_clause_node, @template_analysis, actual_dest, @dest_analysis))
              next
            end

            (region[:start_line]..region[:end_line]).each do |line_num|
              line = region_analysis.line_at(line_num)&.chomp || ""
              if node_preference == :template && region_analysis.equal?(@template_analysis) && template_inline_by_line[line_num].empty?
                dest_clause_line = begin_clause_line_map[line_num]
                dest_clause_inline = dest_clause_line ? dest_inline_by_line[dest_clause_line] : []
                line = append_inline_comment_entries(line, dest_clause_inline) if dest_clause_inline.any?
              end
              @result.add_line(
                line,
                decision: decision,
                template_line: region_analysis.equal?(@template_analysis) ? line_num : nil,
                dest_line: region_analysis.equal?(@dest_analysis) ? line_num : nil,
              )
            end
          end
        end

        # Add the closing 'end'
        end_line = source_analysis.line_at(source_node.location.end_line)
        if node_preference == :template && template_inline_by_line[actual_template.location.end_line].empty?
          dest_end_inline = dest_inline_by_line[actual_dest.location.end_line]
          end_line = append_inline_comment_entries(end_line.to_s.chomp, dest_end_inline) if dest_end_inline.any?
        end
        @result.add_line(
          end_line.chomp,
          decision: decision,
          template_line: (node_preference == :template) ? source_node.location.end_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.end_line : nil,
        )

        template_trailing_comments = external_trailing_comments_for(actual_template)
        dest_trailing_comments = external_trailing_comments_for(actual_dest)

        if node_preference == :template
          trailing_comments = template_trailing_comments.any? ? template_trailing_comments : dest_trailing_comments
          trailing_analysis = template_trailing_comments.any? ? @template_analysis : @dest_analysis
        else
          trailing_comments = dest_trailing_comments
          trailing_analysis = @dest_analysis
        end

        if trailing_comments.any?
          emitted_dest_line = emit_external_trailing_comments(
            @result,
            trailing_comments,
            source_node: trailing_analysis.equal?(@template_analysis) ? actual_template : actual_dest,
            analysis: trailing_analysis,
            source: trailing_analysis.equal?(@template_analysis) ? :template : :destination,
            decision: decision,
          )
          last_emitted_dest_line = emitted_dest_line if trailing_analysis.equal?(@dest_analysis)
          return {last_emitted_dest_line: last_emitted_dest_line}
        end

        # Add trailing blank line if needed for separation (same logic as add_node_to_result)
        trailing_line = source_node.location.end_line + 1
        trailing_content = source_analysis.line_at(trailing_line)
        if trailing_content && trailing_content.strip.empty?
          if node_preference == :template
            @result.add_line("", decision: decision, template_line: trailing_line)
          else
            @result.add_line("", decision: decision, dest_line: trailing_line)
          end
        end

        {last_emitted_dest_line: last_emitted_dest_line}
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
        when Prism::BeginNode
          clause_start_line = begin_node_clause_start_line(node)
          clause_start_line ? clause_start_line - 1 : body_statements.last.location.end_line
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
