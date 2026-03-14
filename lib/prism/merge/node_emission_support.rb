# frozen_string_literal: true

module Prism
  module Merge
    class NodeEmissionSupport
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def emit_dest_prefix_lines(result:, analysis:)
        merger.instance_variable_set(:@dest_prefix_comment_lines, Set.new)
        return 0 if analysis.statements.empty?

        first_node = analysis.statements.first
        leading_comments = first_node.location.respond_to?(:leading_comments) ? first_node.location.leading_comments : []
        first_content_line = leading_comments.any? ? leading_comments.first.location.start_line : first_node.location.start_line
        last_emitted = 0

        if first_content_line > 1
          (1...first_content_line).each do |line_num|
            line = analysis.line_at(line_num)&.chomp || ""
            result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
            dest_prefix_comment_lines << line_num
            last_emitted = line_num
          end
        end

        magic_end_index = -1
        leading_comments.each_with_index do |comment, idx|
          if shebang_comment?(comment)
            break unless idx.zero? && comment.location.start_line == 1

            magic_end_index = idx
            next
          end

          break unless prism_magic_comment?(comment)

          magic_end_index = idx
        end

        return last_emitted if magic_end_index < 0

        (0..magic_end_index).each do |idx|
          comment = leading_comments[idx]
          line_num = comment.location.start_line
          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          if last_emitted > 0 && line_num > last_emitted + 1
            ((last_emitted + 1)...line_num).each do |gap_num|
              gap = analysis.line_at(gap_num)&.chomp || ""
              result.add_line(gap, decision: MergeResult::DECISION_KEPT_DEST, dest_line: gap_num)
              dest_prefix_comment_lines << gap_num
            end
          end

          result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
          dest_prefix_comment_lines << line_num
          last_emitted = line_num
        end

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
            dest_prefix_comment_lines << gap_num
            last_emitted = gap_num
          end
        end

        last_emitted
      end

      def emit_dest_gap_lines(result:, analysis:, last_output_line:, next_node:)
        return last_output_line if last_output_line == 0

        leading_comments = next_node.location.respond_to?(:leading_comments) ? next_node.location.leading_comments : []
        next_start_line = leading_comments.any? ? leading_comments.first.location.start_line : next_node.location.start_line
        gap_start = last_output_line + 1
        return last_output_line if gap_start >= next_start_line

        (gap_start...next_start_line).each do |line_num|
          line = analysis.line_at(line_num)&.chomp || ""
          next unless line.strip.empty?

          result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
        end

        last_output_line
      end

      def emit_matched_template_node(result:, template_node:, dest_node:)
        decision = MergeResult::DECISION_KEPT_TEMPLATE
        last_emitted_dest_line = nil

        template_analysis = merger.template_analysis
        dest_analysis = merger.dest_analysis
        template_leading = merger.send(:filtered_leading_comments_for, template_node, :template)
        dest_leading = merger.send(:filtered_leading_comments_for, dest_node, :destination)

        leading_comments = template_leading[:comments]
        leading_analysis = template_analysis
        prev_comment_line = template_leading[:last_skipped_line]

        if leading_comments.empty? && dest_leading[:comments].any?
          leading_comments = dest_leading[:comments]
          leading_analysis = dest_analysis
          prev_comment_line = nil
        end

        merger.send(
          :emit_leading_comments,
          result,
          leading_comments,
          analysis: leading_analysis,
          source: leading_analysis.equal?(template_analysis) ? :template : :destination,
          decision: decision,
          prev_comment_line: prev_comment_line,
        )

        if leading_analysis.equal?(dest_analysis) && leading_comments.any?
          last_emitted_dest_line = leading_comments.last.location.start_line
        end

        if leading_comments.any?
          emitted_gap_line = merger.send(
            :emit_blank_lines_between,
            result,
            last_comment_line: leading_comments.last.location.start_line,
            next_content_line: leading_analysis.equal?(template_analysis) ? template_node.location.start_line : dest_node.location.start_line,
            analysis: leading_analysis,
            source: leading_analysis.equal?(template_analysis) ? :template : :destination,
            decision: decision,
          )
          last_emitted_dest_line = emitted_gap_line if leading_analysis.equal?(dest_analysis) && emitted_gap_line
        end

        template_inline_entries = template_analysis.send(:owner_inline_comment_entries, template_node)
        dest_inline_entries = dest_analysis.send(:owner_inline_comment_entries, dest_node)
        inline_entries = template_inline_entries.any? ? template_inline_entries : dest_inline_entries

        template_node_source_lines(template_node, template_analysis).each_with_index do |line, index|
          line_num = template_node.location.start_line + index

          if index == template_node_source_lines(template_node, template_analysis).length - 1 &&
              template_inline_entries.empty? && inline_entries.any?
            line = merger.send(:append_inline_comment_entries, line, inline_entries)
          end

          result.add_line(line, decision: decision, template_line: line_num)
        end

        template_trailing_comments = merger.send(:wrapper_comment_support).external_trailing_comments_for(template_node)
        dest_trailing_comments = merger.send(:wrapper_comment_support).external_trailing_comments_for(dest_node)
        trailing_comments = template_trailing_comments.any? ? template_trailing_comments : dest_trailing_comments
        trailing_analysis = template_trailing_comments.any? ? template_analysis : dest_analysis
        trailing_source = trailing_analysis.equal?(template_analysis) ? :template : :destination
        trailing_node = trailing_analysis.equal?(template_analysis) ? template_node : dest_node

        if trailing_comments.any?
          emitted_dest_line = merger.send(
            :emit_external_trailing_comments,
            result,
            trailing_comments,
            source_node: trailing_node,
            analysis: trailing_analysis,
            source: trailing_source,
            decision: decision,
          )
          last_emitted_dest_line = emitted_dest_line if trailing_analysis.equal?(dest_analysis) && emitted_dest_line
          return {last_emitted_dest_line: last_emitted_dest_line}
        end

        trailing_line = template_node.location.end_line + 1
        trailing_content = template_analysis.line_at(trailing_line)
        result.add_line("", decision: decision, template_line: trailing_line) if trailing_content && trailing_content.strip.empty?

        {last_emitted_dest_line: last_emitted_dest_line}
      end

      def emit_node(result:, node:, analysis:, source:)
        decision = source == :template ? MergeResult::DECISION_KEPT_TEMPLATE : MergeResult::DECISION_KEPT_DEST
        leading = merger.send(:filtered_leading_comments_for, node, source)
        leading_comments = leading[:comments]
        inline_comment_entries = analysis.send(:owner_inline_comment_entries, node)

        merger.send(
          :emit_leading_comments,
          result,
          leading_comments,
          analysis: analysis,
          source: source,
          decision: decision,
          prev_comment_line: source == :template ? leading[:last_skipped_line] : nil,
        )

        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          if node.location.start_line > last_comment_line + 1
            ((last_comment_line + 1)...node.location.start_line).each do |line_num|
              next if dest_prefix_comment_lines.include?(line_num)

              line = analysis.line_at(line_num)&.chomp || ""
              if source == :template
                result.add_line(line, decision: decision, template_line: line_num)
              else
                result.add_line(line, decision: decision, dest_line: line_num)
              end
            end
          end
        end

        source_lines = node_source_lines(node, analysis)
        source_lines.each_with_index do |line, index|
          line_num = node.location.start_line + index

          if index == source_lines.length - 1 && partial_same_line_node?(node, analysis) && inline_comment_entries.any?
            line = append_owned_inline_entries(line, inline_comment_entries)
          end

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end
        end

        trailing_line = node.location.end_line + 1
        trailing_content = analysis.line_at(trailing_line)
        if trailing_content && trailing_content.strip.empty?
          if source == :template
            result.add_line("", decision: decision, template_line: trailing_line)
          else
            result.add_line("", decision: decision, dest_line: trailing_line)
          end
        end

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

      private

      def template_node_source_lines(node, analysis)
        node_source_lines(node, analysis)
      end

      def append_owned_inline_entries(line, entries)
        merger.send(:append_inline_comment_entries, line, entries)
      end

      def node_source_lines(node, analysis)
        if partial_same_line_node?(node, analysis)
          ["#{line_indentation(analysis, node.location.start_line)}#{node.slice}"]
        else
          (node.location.start_line..node.location.end_line).map do |line_num|
            analysis.line_at(line_num)&.chomp || ""
          end
        end
      end

      def partial_same_line_node?(node, analysis)
        return false unless node.location.start_line == node.location.end_line

        line_num = node.location.start_line
        line_start_offset = analysis.lines.take(line_num - 1).sum(&:length)
        line_end_offset = line_start_offset + analysis.line_at(line_num).to_s.length
        prefix = analysis.source.byteslice(line_start_offset...node_start_offset(node)).to_s
        suffix = analysis.source.byteslice(node_end_offset(node)...line_end_offset).to_s
        prefix_has_code = !prefix.strip.empty?
        suffix_content = suffix.sub(/\r?\n\z/, "").lstrip
        suffix_has_code = !suffix_content.empty? && !suffix_content.start_with?("#")

        prefix_has_code || suffix_has_code
      end

      def node_start_offset(node)
        if node.location.respond_to?(:start_offset)
          node.location.start_offset
        elsif node.respond_to?(:start_byte)
          node.start_byte
        else
          0
        end
      end

      def node_end_offset(node)
        if node.location.respond_to?(:end_offset)
          node.location.end_offset
        elsif node.respond_to?(:end_byte)
          node.end_byte
        else
          node_start_offset(node) + node.slice.to_s.bytesize
        end
      end

      def line_indentation(analysis, line_num)
        analysis.line_at(line_num).to_s[/\A\s*/].to_s
      end

      def prism_magic_comment?(comment)
        text = comment.slice.sub(/\A#\s*/, "").strip
        Comment::Line::MAGIC_COMMENT_PATTERNS.any? { |_, pattern| text.match?(pattern) }
      end

      def shebang_comment?(comment)
        comment.slice.start_with?("#!")
      end

      def dest_prefix_comment_lines
        merger.instance_variable_get(:@dest_prefix_comment_lines) || Set.new
      end
    end
  end
end
