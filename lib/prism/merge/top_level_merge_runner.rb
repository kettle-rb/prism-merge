# frozen_string_literal: true

module Prism
  module Merge
    class TopLevelMergeRunner
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def merge
        return merger.send(:comment_only_file_merger).merge if comment_only_merge?

        template_by_signature = merger.send(:build_signature_map, merger.template_analysis)
        dest_by_signature = merger.send(:build_signature_map, merger.dest_analysis)
        consumed_template_indices = Set.new
        sig_cursor = Hash.new(0)
        output_dest_line_ranges = []
        last_output_dest_line = merger.send(:emit_dest_prefix_lines, merger.result, merger.dest_analysis)

        emit_template_only_nodes(dest_by_signature, consumed_template_indices)

        merger.dest_analysis.statements.each do |dest_node|
          last_output_dest_line = process_dest_node(
            dest_node: dest_node,
            template_by_signature: template_by_signature,
            consumed_template_indices: consumed_template_indices,
            sig_cursor: sig_cursor,
            output_dest_line_ranges: output_dest_line_ranges,
            last_output_dest_line: last_output_dest_line,
          )
        end

        emit_dest_postlude_lines(last_output_dest_line)

        merger.result
      end

      private

      def comment_only_merge?
        merger.comment_only_file?(merger.template_analysis) && merger.comment_only_file?(merger.dest_analysis)
      end

      def emit_template_only_nodes(dest_by_signature, consumed_template_indices)
        return unless merger.add_template_only_nodes

        merger.template_analysis.statements.each_with_index do |template_node, template_index|
          template_signature = merger.template_analysis.generate_signature(template_node)
          next if template_signature && dest_by_signature.key?(template_signature)

          merger.send(:add_node_to_result, merger.result, template_node, merger.template_analysis, :template)
          consumed_template_indices << template_index
        end
      end

      def process_dest_node(dest_node:, template_by_signature:, consumed_template_indices:, sig_cursor:, output_dest_line_ranges:, last_output_dest_line:)
        node_range = node_offset_range(dest_node)
        return last_output_dest_line if already_output?(node_range, output_dest_line_ranges)

        dest_signature = merger.dest_analysis.generate_signature(dest_node)
        last_output_dest_line = merger.send(:emit_dest_gap_lines, merger.result, merger.dest_analysis, last_output_dest_line, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis

        if dest_signature && template_by_signature.key?(dest_signature)
          template_info, cursor = next_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor,
          )

          if template_info
            emission = process_matched_node(
              dest_node: dest_node,
              dest_signature: dest_signature,
              template_info: template_info,
              cursor: cursor,
              consumed_template_indices: consumed_template_indices,
              sig_cursor: sig_cursor,
              output_dest_line_ranges: output_dest_line_ranges,
              node_range: node_range,
              last_output_dest_line: last_output_dest_line,
            )
            last_output_dest_line = emission[:last_output_dest_line]
            output_node = emission[:output_node]
            output_analysis = emission[:output_analysis]
          else
            merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
            output_dest_line_ranges << node_range
          end
        else
          merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
          output_dest_line_ranges << node_range
        end

        advance_last_output_dest_line(
          last_output_dest_line: last_output_dest_line,
          dest_node: dest_node,
          output_node: output_node,
          output_analysis: output_analysis,
        )
      end

      def already_output?(node_range, output_dest_line_ranges)
        output_dest_line_ranges.any? do |range|
          range[:start_offset] <= node_range[:start_offset] && node_range[:end_offset] <= range[:end_offset]
        end
      end

      def node_offset_range(node)
        location = node.location
        start_offset = if location.respond_to?(:start_offset)
          location.start_offset
        elsif node.respond_to?(:start_byte)
          node.start_byte
        else
          location.start_line
        end

        end_offset = if location.respond_to?(:end_offset)
          location.end_offset
        elsif node.respond_to?(:end_byte)
          node.end_byte
        else
          location.end_line
        end

        {
          start_offset: start_offset,
          end_offset: end_offset,
        }
      end

      def next_template_match(candidates:, signature:, sig_cursor:)
        cursor = sig_cursor[signature]

        candidate = candidates[cursor]
        return [candidate, cursor] if candidate

        [nil, cursor]
      end

      def process_matched_node(dest_node:, dest_signature:, template_info:, cursor:, consumed_template_indices:, sig_cursor:, output_dest_line_ranges:, node_range:, last_output_dest_line:)
        template_node = template_info[:node]
        consumed_template_indices << template_info[:index]
        sig_cursor[dest_signature] = cursor + 1
        output_dest_line_ranges << node_range

        if merger.send(:should_merge_recursively?, template_node, dest_node)
          process_recursive_match(
            template_node: template_node,
            dest_node: dest_node,
            last_output_dest_line: last_output_dest_line,
          )
        else
          process_non_recursive_match(
            template_node: template_node,
            dest_node: dest_node,
            last_output_dest_line: last_output_dest_line,
          )
        end
      end

      def process_recursive_match(template_node:, dest_node:, last_output_dest_line:)
        recursive_emission = merger.send(:merge_node_body_recursively, template_node, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis

        if merger.send(:preference_for_node, template_node, dest_node) == :template
          output_node = unwrap_node(template_node)
          output_analysis = merger.template_analysis
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, recursive_emission),
          output_node: output_node,
          output_analysis: output_analysis,
        }
      end

      def process_non_recursive_match(template_node:, dest_node:, last_output_dest_line:)
        output_node = dest_node
        output_analysis = merger.dest_analysis
        emission = nil

        if merger.send(:preference_for_node, template_node, dest_node) == :template
          emission = merger.send(:add_matched_template_node_to_result, merger.result, template_node, dest_node)
          output_node = template_node
          output_analysis = merger.template_analysis
        else
          merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, emission),
          output_node: output_node,
          output_analysis: output_analysis,
        }
      end

      def emission_last_output(last_output_dest_line, emission)
        emitted_dest_line = emission&.dig(:last_emitted_dest_line)
        return last_output_dest_line unless emitted_dest_line

        [last_output_dest_line, emitted_dest_line].max
      end

      def advance_last_output_dest_line(last_output_dest_line:, dest_node:, output_node:, output_analysis:)
        updated_last_output_dest_line = [last_output_dest_line, dest_node.location.end_line].max
        actual_output_end = unwrap_node(output_node).location.end_line
        trailing_line_num = actual_output_end + 1
        trailing_content = output_analysis.line_at(trailing_line_num)
        return updated_last_output_dest_line unless trailing_content && trailing_content.strip.empty?

        trailing_dest_line = dest_node.location.end_line + 1
        dest_trailing = merger.dest_analysis.line_at(trailing_dest_line)
        return updated_last_output_dest_line unless dest_trailing && dest_trailing.strip.empty?

        [updated_last_output_dest_line, trailing_dest_line].max
      end

      def emit_dest_postlude_lines(last_output_dest_line)
        remaining_line_range = (last_output_dest_line + 1)..merger.dest_analysis.lines.length
        return if remaining_line_range.begin > remaining_line_range.end

        remaining_line_range.each do |line_num|
          line = merger.dest_analysis.line_at(line_num).to_s.chomp
          next unless line.strip.empty?

          merger.result.add_line(
            line,
            decision: MergeResult::DECISION_KEPT_DEST,
            dest_line: line_num,
          )
        end
      end

      def unwrap_node(node)
        node.respond_to?(:unwrap) ? node.unwrap : node
      end
    end
  end
end
