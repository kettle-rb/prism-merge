# frozen_string_literal: true

require "set"

module Prism
  module Merge
    # Resolves conflicts in boundaries between anchors using structural
    # signatures and comment preservation strategies.
    #
    # ConflictResolver is responsible for the core merge logic within boundaries
    # (sections where template and destination differ). It:
    # - Matches nodes by structural signature
    # - Decides which version to keep based on preference
    # - Preserves trailing blank lines for proper spacing
    # - Handles template-only and destination-only nodes
    #
    # @example Basic usage (via SmartMerger)
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(boundary, result)
    #
    # @see SmartMerger
    # @see FileAnalysis
    # @see MergeResult
    class ConflictResolver
      # @return [FileAnalysis] Analysis of the template file
      attr_reader :template_analysis

      # @return [FileAnalysis] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [Symbol] Preference for signature matches (:template or :destination)
      attr_reader :signature_match_preference

      # @return [Boolean] Whether to add template-only nodes
      attr_reader :add_template_only_nodes

      # Creates a new ConflictResolver for handling merge conflicts.
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      #
      # @param signature_match_preference [Symbol] Which version to prefer when
      #   nodes have matching signatures but different content:
      #   - `:destination` (default) - Keep destination version (customizations)
      #   - `:template` - Use template version (updates)
      #
      # @param add_template_only_nodes [Boolean] Whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add template-only nodes to result
      #
      # @example Create resolver for Appraisals (destination wins)
      #   resolver = ConflictResolver.new(
      #     template_analysis,
      #     dest_analysis,
      #     signature_match_preference: :destination,
      #     add_template_only_nodes: false
      #   )
      #
      # @example Create resolver for version files (template wins)
      #   resolver = ConflictResolver.new(
      #     template_analysis,
      #     dest_analysis,
      #     signature_match_preference: :template,
      #     add_template_only_nodes: true
      #   )
      def initialize(template_analysis, dest_analysis, signature_match_preference: :destination, add_template_only_nodes: false)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @signature_match_preference = signature_match_preference
        @add_template_only_nodes = add_template_only_nodes
      end

      # Resolve a boundary by deciding which content to keep.
      # If the boundary contains a `kettle-dev:freeze` block, the entire
      # block from the destination is preserved.
      # @param boundary [FileAligner::Boundary] Boundary to resolve
      # @param result [MergeResult] Result object to populate
      def resolve(boundary, result)
        # Extract content from both sides
        template_content = extract_boundary_content(@template_analysis, boundary.template_range)
        dest_content = extract_boundary_content(@dest_analysis, boundary.dest_range)

        # If both sides are empty, nothing to do
        return if template_content[:lines].empty? && dest_content[:lines].empty?

        # If one side is empty, use the other
        if template_content[:lines].empty?
          add_content_to_result(dest_content, result, :destination, MergeResult::DECISION_KEPT_DEST)
          return
        end

        if dest_content[:lines].empty?
          # Only add template-only content if the flag allows it
          if @add_template_only_nodes
            add_content_to_result(template_content, result, :template, MergeResult::DECISION_KEPT_TEMPLATE)
          end
          return
        end

        # Both sides have content - perform intelligent merge
        merge_boundary_content(template_content, dest_content, boundary, result)
      end

      private

      def extract_boundary_content(analysis, line_range)
        return {lines: [], nodes: [], has_freeze_block: false, line_range: nil} unless line_range

        lines = []
        line_range.each do |line_num|
          lines << analysis.line_at(line_num)
        end

        # Find nodes that intersect with this range
        nodes = analysis.nodes_with_comments.select do |node_info|
          node_range = node_info[:line_range]
          ranges_overlap?(node_range, line_range)
        end

        # Check for freeze blocks
        has_freeze_block = line_range.any? { |line_num| analysis.in_freeze_block?(line_num) }

        {
          lines: lines.map(&:chomp),
          nodes: nodes,
          has_freeze_block: has_freeze_block,
          line_range: line_range,
        }
      end

      def ranges_overlap?(range1, range2)
        range1.begin <= range2.end && range2.begin <= range1.end
      end

      def add_content_to_result(content, result, source, decision)
        return if content[:lines].empty?

        start_line = content[:line_range].begin
        result.add_lines_from(
          content[:lines],
          decision: decision,
          source: source,
          start_line: start_line,
        )
      end

      def merge_boundary_content(template_content, dest_content, _boundary, result)
        # Strategy: Process nodes in order using signature matching.
        # FreezeNodes from destination are always preferred to preserve customizations.

        template_nodes = template_content[:nodes]
        dest_nodes = dest_content[:nodes]

        # Track which dest nodes have been matched
        matched_dest_indices = Set.new

        # Check if there are any FreezeNodes in destination - they always win
        dest_freeze_nodes = dest_nodes.select { |n| n[:node].is_a?(FreezeNode) }

        if dest_freeze_nodes.any?
          # Add all destination freeze blocks as-is
          dest_freeze_nodes.each do |freeze_node_info|
            result.add_node(
              freeze_node_info,
              decision: MergeResult::DECISION_FREEZE_BLOCK,
              source: :destination,
              source_analysis: @dest_analysis,
            )
            matched_dest_indices << freeze_node_info[:index]

            # Mark any template nodes within this freeze block range as processed
            freeze_range = freeze_node_info[:line_range]
            template_nodes.each do |t_node_info|
              if freeze_range.cover?(t_node_info[:line_range].begin) &&
                  freeze_range.cover?(t_node_info[:line_range].end)
                # Template node is inside freeze block, skip it
                # (we'll handle this by checking if it overlaps with a freeze block)
              end
            end
          end
        end

        # Build signature map for destination nodes (excluding already-matched freeze nodes)
        dest_sig_map = build_signature_map(dest_nodes.reject { |n| matched_dest_indices.include?(n[:index]) })

        # Build a set of line numbers that are covered by leading comments of nodes
        # so we don't duplicate them when processing non-node lines
        leading_comment_lines = Set.new
        template_nodes.each do |node_info|
          node_info[:leading_comments].each do |comment|
            leading_comment_lines << comment.location.start_line
          end
        end

        # Process template line by line, adding nodes and non-node lines in order
        template_line_range = template_content[:line_range]
        return unless template_line_range

        current_line = template_line_range.begin
        # Track if we're in a sequence of template-only nodes
        in_template_only_sequence = false

        sorted_nodes = template_nodes.sort_by { |n| n[:line_range].begin }

        sorted_nodes.each_with_index do |t_node_info, idx|
          node_start = t_node_info[:line_range].begin
          node_end = t_node_info[:line_range].end

          # Skip template nodes that overlap with destination freeze blocks
          overlaps_freeze = dest_freeze_nodes.any? do |freeze_info|
            freeze_range = freeze_info[:line_range]
            node_start.between?(freeze_range.begin, freeze_range.end) ||
              node_end.between?(freeze_range.begin, freeze_range.end)
          end

          if overlaps_freeze
            current_line = node_end + 1
            next
          end

          # Check if this node will be matched or is template-only
          sig = t_node_info[:signature]
          is_matched = dest_sig_map[sig]&.any?

          # Calculate the range that includes trailing blank lines up to the next node
          # This way, blank lines "belong" to the preceding node
          next_node_start = (idx + 1 < sorted_nodes.length) ? sorted_nodes[idx + 1][:line_range].begin : template_line_range.end + 1

          # Find trailing blank lines after this node
          trailing_blank_end = node_end
          (node_end + 1...next_node_start).each do |line_num|
            break if !template_line_range.cover?(line_num)
            line = @template_analysis.line_at(line_num)
            break if !line.strip.empty? # Stop at first non-blank line
            trailing_blank_end = line_num
          end

          # Add any non-node, non-blank lines before this node (e.g., comments not attached to nodes)
          if (in_template_only_sequence && !is_matched) || (!is_matched && !@add_template_only_nodes)
            # Skip lines before template-only nodes in a sequence OR when add_template_only_nodes is false
            current_line = node_start
          else
            while current_line < node_start
              if template_line_range.cover?(current_line) && !leading_comment_lines.include?(current_line)
                line = @template_analysis.line_at(current_line)
                # Only add non-blank lines here (blank lines belong to preceding node)
                unless line.strip.empty?
                  add_line_safe(result, line.chomp, decision: MergeResult::DECISION_KEPT_TEMPLATE, template_line: current_line)
                end
              end
              current_line += 1
            end
          end

          # Add the node (use configured preference when signatures match)
          # Include trailing blank lines with the node
          if is_matched
            # Match found - use preference to decide which version
            if @signature_match_preference == :template
              # Use template version (it's the canonical/updated version)
              result.add_node(
                t_node_info,
                decision: MergeResult::DECISION_REPLACED,
                source: :template,
                source_analysis: @template_analysis,
              )
            else
              # Use destination version (it has the customizations)
              dest_matches = dest_sig_map[sig]
              result.add_node(
                dest_matches.first,
                decision: MergeResult::DECISION_REPLACED,
                source: :destination,
                source_analysis: @dest_analysis,
              )
            end

            # Mark matching dest nodes as processed
            dest_matches = dest_sig_map[sig]
            dest_matches.each do |d_node_info|
              matched_dest_indices << d_node_info[:index]
            end

            # Calculate trailing blank lines from destination to preserve original spacing
            # Use the first matching dest node to determine blank line spacing
            d_node_info = dest_matches.first
            d_node = d_node_info[:node]
            d_node_end = d_node.location.end_line
            # Find how many blank lines follow this node in destination
            d_trailing_blank_end = d_node_end
            if d_node_info[:index] < dest_nodes.size - 1
              next_dest_info = dest_nodes[d_node_info[:index] + 1]
              # Find where next node's content actually starts (first leading comment or node itself)
              next_content_start = if next_dest_info[:leading_comments].any?
                next_dest_info[:leading_comments].first.location.start_line
              else
                next_dest_info[:node].location.start_line
              end

              # Find all blank lines between this node end and next node's content
              (d_node_end + 1...next_content_start).each do |line_num|
                line_content = @dest_analysis.line_at(line_num)
                if line_content.strip.empty?
                  d_trailing_blank_end = line_num
                else
                  # Stop at first non-blank line
                  break
                end
              end
            end

            # Add trailing blank lines from destination (preserving destination spacing)
            (d_node_end + 1..d_trailing_blank_end).each do |line_num|
              line = @dest_analysis.line_at(line_num)
              add_line_safe(result, line.chomp, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
            end

            in_template_only_sequence = false
          elsif @add_template_only_nodes
            # No match - this is a template-only node
            result.add_node(
              t_node_info,
              decision: MergeResult::DECISION_KEPT_TEMPLATE,
              source: :template,
              source_analysis: @template_analysis,
            )

            # Add trailing blank lines from template
            (node_end + 1..trailing_blank_end).each do |line_num|
              line = @template_analysis.line_at(line_num)
              add_line_safe(result, line.chomp, decision: MergeResult::DECISION_KEPT_TEMPLATE, template_line: line_num)
            end

            in_template_only_sequence = false
          # Add the template-only node
          else
            # Skip template-only nodes (don't add template nodes that don't exist in destination)
            in_template_only_sequence = true
          end

          current_line = trailing_blank_end + 1
        end

        # Add any remaining template lines after the last node
        # But skip if we ended in a template-only sequence
        unless in_template_only_sequence
          while current_line <= template_line_range.end
            if !leading_comment_lines.include?(current_line)
              line = @template_analysis.line_at(current_line)
              add_line_safe(result, line.chomp, decision: MergeResult::DECISION_KEPT_TEMPLATE, template_line: current_line)
            end
            current_line += 1
          end
        end

        # Add dest-only nodes (nodes that weren't matched)
        dest_only_nodes = dest_nodes.select { |d| !matched_dest_indices.include?(d[:index]) }

        unless dest_only_nodes.empty?
          # Add a blank line before appending dest-only nodes if the result doesn't already end with one
          if result.lines.any? && !result.lines.last.strip.empty?
            add_line_safe(result, "", decision: MergeResult::DECISION_KEPT_TEMPLATE)
          end

          dest_only_nodes.each_with_index do |d_node_info, idx|
            result.add_node(
              d_node_info,
              decision: MergeResult::DECISION_APPENDED,
              source: :destination,
              source_analysis: @dest_analysis,
            )

            # Add trailing blank lines for each dest-only node
            d_node = d_node_info[:node]
            d_node_end = d_node.location.end_line
            d_trailing_blank_end = d_node_end

            # Find trailing blank lines up to the next node or end of boundary
            if idx < dest_only_nodes.size - 1
              # Not the last dest-only node - look for next dest-only node
              next_dest_info = dest_only_nodes[idx + 1]
              # Find where next node's content actually starts (first leading comment or node itself)
              next_content_start = if next_dest_info[:leading_comments].any?
                next_dest_info[:leading_comments].first.location.start_line
              else
                next_dest_info[:node].location.start_line
              end

              # Collect blank lines between this node end and next node's content
              (d_node_end + 1...next_content_start).each do |line_num|
                line_content = @dest_analysis.line_at(line_num)
                if line_content.strip.empty?
                  d_trailing_blank_end = line_num
                else
                  break
                end
              end
            else
              # This is the last dest-only node - look for trailing blanks up to boundary end
              # Check lines after this node for blank lines
              boundary_end = dest_content[:line_range].end
              line_num = d_node_end + 1
              while line_num <= boundary_end
                line_content = @dest_analysis.line_at(line_num)
                if line_content.strip.empty?
                  d_trailing_blank_end = line_num
                  line_num += 1
                else
                  break
                end
              end
            end

            # Add trailing blank lines from destination
            (d_node_end + 1..d_trailing_blank_end).each do |line_num|
              line = @dest_analysis.line_at(line_num)
              add_line_safe(result, line.chomp, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
            end
          end
        end
      end

      def build_signature_map(nodes)
        map = Hash.new { |h, k| h[k] = [] }
        nodes.each do |node_info|
          sig = node_info[:signature]
          map[sig] << node_info if sig
        end
        map
      end

      # Add a line to result but avoid adding multiple consecutive blank lines.
      def add_line_safe(result, content, **kwargs)
        if content.strip.empty?
          # If last line is also blank, skip adding to collapse runs of blank lines
          return if result.lines.any? && result.lines.last.strip.empty?
        end

        result.add_line(content, **kwargs)
      end

      def handle_orphan_lines(template_content, dest_content, result)
        # With CommentNodes integrated into statements, there should be far fewer orphan lines
        # Orphan lines are now only truly standalone content like blank lines or
        # inline content not attached to nodes.

        # Find lines that aren't part of any node (pure comments, blank lines)
        template_orphans = find_orphan_lines(@template_analysis, template_content[:line_range], template_content[:nodes])
        dest_orphans = find_orphan_lines(@dest_analysis, dest_content[:line_range], dest_content[:nodes])

        # Add template orphans first
        template_orphans.each do |line_num|
          line = @template_analysis.line_at(line_num)
          result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_KEPT_TEMPLATE,
            template_line: line_num,
          )
        end

        # Then add unique destination orphans (ones not in template)
        template_orphan_content = Set.new(template_orphans.map { |ln| @template_analysis.normalized_line(ln) })

        dest_orphans.each do |line_num|
          content = @dest_analysis.normalized_line(line_num)
          next if template_orphan_content.include?(content)

          # Add unique destination orphan
          line = @dest_analysis.line_at(line_num)
          result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_APPENDED,
            dest_line: line_num,
          )
        end
      end

      def find_orphan_lines(analysis, line_range, nodes)
        return [] unless line_range

        # Get all lines covered by nodes
        covered_lines = Set.new
        nodes.each do |node_info|
          node_range = node_info[:line_range]
          node_range.each { |ln| covered_lines << ln }

          # Also cover comment lines
          node_info[:leading_comments].each do |comment|
            covered_lines << comment.location.start_line
          end
        end

        # Find uncovered lines
        orphans = []
        line_range.each do |line_num|
          next if covered_lines.include?(line_num)

          # Check if this line has content (not just blank)
          line = analysis.line_at(line_num)
          orphans << line_num if line && !line.strip.empty?
        end

        orphans
      end
    end
  end
end
