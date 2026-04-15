# frozen_string_literal: true

module Prism
  module Merge
    class WrapperCommentSupport
      include Prism::Merge::SourceLineLookup

      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def filtered_leading_comments_for(node, source)
        all_leading_comments = node.location.respond_to?(:leading_comments) ? node.location.leading_comments : []
        last_skipped_line = nil
        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)
        prefix_line_numbers = Prism::Merge::MagicCommentSupport.prefix_comment_line_numbers_for_comments(all_leading_comments)

        # Lines claimed by promoted BlockDirective nodes (e.g. freeze/nocov markers
        # that Prism hoisted onto this node as leading_comments). Skip them so they
        # are not re-emitted after already appearing inside the BlockDirective's lines.
        dest_claimed = merger.dest_analysis.respond_to?(:claimed_lines) ? merger.dest_analysis.claimed_lines : Set.new
        template_claimed = merger.template_analysis.respond_to?(:claimed_lines) ? merger.template_analysis.claimed_lines : Set.new
        source_claimed = (source == :destination) ? dest_claimed : template_claimed

        comments = if source == :destination
          all_leading_comments.reject do |comment|
            ln = comment.location.start_line
            if dest_prefix_comment_lines&.include?(ln)
              last_skipped_line = ln
              true
            elsif source_claimed.include?(ln)
              last_skipped_line = ln
              true
            end
          end
        elsif dest_prefix_comment_lines&.any?
          all_leading_comments.reject do |comment|
            ln = comment.location.start_line
            if prefix_line_numbers.include?(ln)
              last_skipped_line = ln
              true
            elsif source_claimed.include?(ln)
              last_skipped_line = ln
              true
            end
          end
        else
          all_leading_comments.reject do |comment|
            ln = comment.location.start_line
            if source_claimed.include?(ln)
              last_skipped_line = ln
              true
            end
          end
        end

        {comments: comments, last_skipped_line: last_skipped_line}
      end

      def comment_attachment_for(node, source:, analysis: nil)
        attachment = cached_comment_augmenter_for(source)&.attachment_for(node)
        return attachment if attachment
        return unless analysis&.respond_to?(:comment_attachment_for)

        analysis.comment_attachment_for(node)
      end

      def orphan_regions_for(node, source:, analysis: nil)
        attachment = comment_attachment_for(node, source: source, analysis: analysis)
        Array(attachment&.orphan_regions)
      end

      def orphan_line_numbers_for(source)
        Array(cached_comment_augmenter_for(source)&.orphan_regions)
          .flat_map { |region| Array(region.nodes) }
          .filter_map { |comment_node| comment_node_line(comment_node) }
          .uniq
      end

      def emit_leading_comments(result, comments, analysis:, source:, decision:, prev_comment_line: nil)
        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)

        comments.each do |comment|
          line_num = comment.location.start_line

          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              next if dest_prefix_comment_lines&.include?(blank_line_num)

              line = required_source_line(
                analysis,
                blank_line_num,
                context: "emitting blank line between leading comments",
              )
              if source == :template
                result.add_line(line, decision: decision, template_line: blank_line_num)
              else
                result.add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          line = required_comment_line(
            analysis,
            comment,
            context: "emitting leading comment",
          )
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

          line = required_source_line(
            analysis,
            line_num,
            context: "emitting blank line between comment region and content",
          )
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

      def emit_comment_region(result, region, analysis:, source:, decision:, previous_line: nil)
        return unless region&.respond_to?(:nodes)
        return if region.respond_to?(:empty?) && region.empty?

        last_emitted_line = nil

        region.nodes.each do |comment_node|
          line_num = comment_node_line(comment_node)
          next unless line_num

          gap_line = emit_blank_lines_between(
            result,
            last_comment_line: previous_line,
            next_content_line: line_num,
            analysis: analysis,
            source: source,
            decision: decision,
          ) if previous_line
          last_emitted_line = gap_line || last_emitted_line

          line = required_source_line(
            analysis,
            line_num,
            context: "emitting comment-region node",
          )
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

      def emit_orphan_regions(result, regions, analysis:, source:, decision:, previous_line: nil)
        last_emitted_line = nil
        current_previous_line = previous_line

        Array(regions).sort_by { |region| region.respond_to?(:start_line) ? region.start_line.to_i : 0 }.each do |region|
          emitted_line = emit_comment_region(
            result,
            region,
            analysis: analysis,
            source: source,
            decision: decision,
            previous_line: current_previous_line,
          )
          next unless emitted_line

          current_previous_line = region.respond_to?(:end_line) ? region.end_line : emitted_line
          last_emitted_line = emitted_line
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

          line = required_comment_line(
            analysis,
            comment,
            context: "emitting external trailing comment",
          )
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
        normalized_entries = Array(entries).filter_map do |entry|
          raw = entry[:raw].to_s.lstrip
          next if raw.empty?

          entry.merge(raw: raw)
        end
        return line if normalized_entries.empty?

        normalized_entries.each_with_index.reduce(line) do |memo, (entry, index)|
          separator = if memo.empty?
            ""
          elsif index.zero?
            entry[:separator].to_s.empty? ? " " : entry[:separator]
          else
            " "
          end

          memo + separator + entry[:raw]
        end
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

          raw = comment.slice.chomp
          {
            line: line_num,
            raw: raw,
            separator: inline_comment_separator_for(line, raw),
          }
        end
      end

      def wrapper_inline_comment_entries_by_line(analysis, node)
        owner_entries = analysis.send(:owner_inline_comment_entries, node)
        wrapper_lines = merger.send(:begin_node_boundary_lines, node)
        raw_entries = wrapper_lines.flat_map { |line_num| line_inline_comment_entries(analysis, line_num) }
        inline_comment_entries_by_line((owner_entries + raw_entries).uniq { |entry| [entry[:line], entry[:raw]] })
      end

      # Returns trailing comments that fall outside the node's own line range.
      #
      # @param node [Prism::Node] The node whose trailing comments to examine
      # @param claimed_lines [Set<Integer>] Line numbers claimed by promoted BlockDirective
      #   nodes. Trailing comments at claimed lines are excluded to prevent duplication
      #   when those lines are already emitted as part of a BlockDirective node's source.
      def external_trailing_comments_for(node, claimed_lines: Set.new)
        trailing_comments = node.location.respond_to?(:trailing_comments) ? node.location.trailing_comments : []
        node_line_range = node.location.start_line..node.location.end_line
        trailing_comments.reject do |comment|
          ln = comment.location.start_line
          node_line_range.cover?(ln) || claimed_lines.include?(ln)
        end
      end

      def inline_comment_separator_for(line_text, raw_comment)
        return if line_text.to_s.empty? || raw_comment.to_s.empty?

        prefix, separator, = line_text.sub(/\r?\n\z/, "").rpartition(raw_comment)
        return unless separator == raw_comment

        prefix[/[ \t]+\z/]
      end

      private

      def cached_comment_augmenter_for(source)
        ivar = (source == :template) ? :@template_comment_augmenter : :@dest_comment_augmenter
        merger.instance_variable_get(ivar)
      end

      def comment_node_line(comment_node)
        return comment_node.line_number if comment_node.respond_to?(:line_number)
        return comment_node.location.start_line if comment_node.respond_to?(:location) && comment_node.location

        nil
      end

      def comment_node_text(comment_node)
        if comment_node.respond_to?(:slice)
          comment_node.slice.to_s.chomp
        elsif comment_node.respond_to?(:text)
          comment_node.text.to_s.chomp
        else
          comment_node.to_s.chomp
        end
      end
    end
  end
end
