# frozen_string_literal: true

module Prism
  module Merge
    class WrapperCommentSupport
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def filtered_leading_comments_for(node, source)
        all_leading_comments = node.location.respond_to?(:leading_comments) ? node.location.leading_comments : []
        last_skipped_line = nil
        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)

        comments = if source == :destination
          all_leading_comments.reject do |comment|
            if dest_prefix_comment_lines&.include?(comment.location.start_line)
              last_skipped_line = comment.location.start_line
              true
            end
          end
        elsif dest_prefix_comment_lines&.any?
          all_leading_comments.reject do |comment|
            if comment.slice.start_with?("#!") || merger.send(:prism_magic_comment?, comment)
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
        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)

        comments.each do |comment|
          line_num = comment.location.start_line

          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              next if dest_prefix_comment_lines&.include?(blank_line_num)

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

        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)
        last_emitted_line = nil

        ((last_comment_line + 1)...next_content_line).each do |line_num|
          next if dest_prefix_comment_lines&.include?(line_num)

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
          last_emitted_line = gap_line || last_emitted_line

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

      def wrapper_inline_comment_entries_by_line(analysis, node)
        owner_entries = analysis.send(:owner_inline_comment_entries, node)
        wrapper_lines = merger.send(:begin_node_boundary_lines, node)
        raw_entries = wrapper_lines.flat_map { |line_num| line_inline_comment_entries(analysis, line_num) }
        inline_comment_entries_by_line((owner_entries + raw_entries).uniq { |entry| [entry[:line], entry[:raw]] })
      end

      def external_trailing_comments_for(node)
        trailing_comments = node.location.respond_to?(:trailing_comments) ? node.location.trailing_comments : []
        node_line_range = node.location.start_line..node.location.end_line
        trailing_comments.reject { |comment| node_line_range.cover?(comment.location.start_line) }
      end
    end
  end
end
