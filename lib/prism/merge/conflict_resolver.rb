# frozen_string_literal: true

require "set"

module Prism
  module Merge
    # Resolves conflicts in boundaries between anchors using structural
    # signatures and comment preservation strategies.
    class ConflictResolver
      attr_reader :template_analysis, :dest_analysis

      def initialize(template_analysis, dest_analysis)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
      end

      # Resolve a boundary by deciding which content to keep
      # @param boundary [FileAligner::Boundary] Boundary to resolve
      # @param result [MergeResult] Result object to populate
      def resolve(boundary, result)
        # Extract content from both sides
        template_content = extract_boundary_content(@template_analysis, boundary.template_range)
        dest_content = extract_boundary_content(@dest_analysis, boundary.dest_range)

        # If destination is in freeze block, always keep destination
        if boundary.dest_range && dest_content[:has_freeze_block]
          add_content_to_result(dest_content, result, :destination, MergeResult::DECISION_FREEZE_BLOCK)
          return
        end

        # If both sides are empty, nothing to do
        return if template_content[:lines].empty? && dest_content[:lines].empty?

        # If one side is empty, use the other
        if template_content[:lines].empty?
          add_content_to_result(dest_content, result, :destination, MergeResult::DECISION_KEPT_DEST)
          return
        end

        if dest_content[:lines].empty?
          add_content_to_result(template_content, result, :template, MergeResult::DECISION_KEPT_TEMPLATE)
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
        # Strategy: Process template content in order, replacing matched nodes with template version
        # and appending dest-only nodes at the end

        template_nodes = template_content[:nodes]
        dest_nodes = dest_content[:nodes]

        # Build signature map for destination nodes
        dest_sig_map = build_signature_map(dest_nodes)

        # Track which dest nodes have been matched
        matched_dest_indices = Set.new

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

        template_nodes.sort_by { |n| n[:line_range].begin }.each do |t_node_info|
          node_start = t_node_info[:line_range].begin

          # Add any non-node lines before this node (excluding leading comment lines)
          while current_line < node_start
            if template_line_range.cover?(current_line) && !leading_comment_lines.include?(current_line)
              line = @template_analysis.line_at(current_line)
              result.add_line(
                line.chomp,
                decision: MergeResult::DECISION_KEPT_TEMPLATE,
                template_line: current_line,
              )
            end
            current_line += 1
          end

          # Add the node (template version, possibly replacing dest version)
          sig = t_node_info[:signature]
          if dest_sig_map[sig]
            # Match found - use template version
            result.add_node(
              t_node_info,
              decision: MergeResult::DECISION_REPLACED,
              source: :template,
              source_analysis: @template_analysis,
            )

            # Mark matching dest nodes as processed
            dest_sig_map[sig].each do |d_node_info|
              matched_dest_indices << d_node_info[:index]
            end
          else
            # No match - add template node
            result.add_node(
              t_node_info,
              decision: MergeResult::DECISION_KEPT_TEMPLATE,
              source: :template,
              source_analysis: @template_analysis,
            )
          end

          current_line = t_node_info[:line_range].end + 1
        end

        # Add any remaining template lines after the last node
        while current_line <= template_line_range.end
          if !leading_comment_lines.include?(current_line)
            line = @template_analysis.line_at(current_line)
            result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_KEPT_TEMPLATE,
              template_line: current_line,
            )
          end
          current_line += 1
        end

        # Add dest-only nodes (nodes that weren't matched)
        dest_nodes.each do |d_node_info|
          next if matched_dest_indices.include?(d_node_info[:index])

          result.add_node(
            d_node_info,
            decision: MergeResult::DECISION_APPENDED,
            source: :destination,
            source_analysis: @dest_analysis,
          )
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

      def handle_orphan_lines(template_content, dest_content, result)
        # Find lines that aren't part of any node (pure comments, blank lines)
        template_orphans = find_orphan_lines(@template_analysis, template_content[:line_range], template_content[:nodes])
        dest_orphans = find_orphan_lines(@dest_analysis, dest_content[:line_range], dest_content[:nodes])

        # For simplicity, prefer template orphans but add unique dest orphans
        # This could be enhanced with more sophisticated comment merging
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
