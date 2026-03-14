# frozen_string_literal: true

module Prism
  module Merge
    class RecursiveNodeBodyMerger
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def merge(template_node:, dest_node:)
        actual_template = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
        actual_dest = dest_node.respond_to?(:unwrap) ? dest_node.unwrap : dest_node
        template_layout = merger.send(:node_body_layout_for, actual_template, merger.template_analysis)
        dest_layout = merger.send(:node_body_layout_for, actual_dest, merger.dest_analysis)

        template_body = merger.send(:extract_node_body, actual_template, merger.template_analysis)
        dest_body = merger.send(:extract_node_body, actual_dest, merger.dest_analysis)

        body_merger = merger.class.new(
          template_body,
          dest_body,
          signature_generator: merger.instance_variable_get(:@raw_signature_generator),
          preference: merger.preference,
          add_template_only_nodes: merger.add_template_only_nodes,
          remove_template_missing_nodes: merger.remove_template_missing_nodes,
          freeze_token: merger.freeze_token,
          max_recursion_depth: merger.max_recursion_depth,
          current_depth: merger.instance_variable_get(:@current_depth) + 1,
          node_typing: merger.node_typing,
        )
        body_result = if template_body.empty? && dest_body.empty?
          nil
        else
          body_merger.merge_result
        end

        node_preference = merger.send(:preference_for_node, template_node, dest_node)
        last_emitted_dest_line = nil

        template_comments = actual_template.location.respond_to?(:leading_comments) ? actual_template.location.leading_comments : []
        dest_comments = actual_dest.location.respond_to?(:leading_comments) ? actual_dest.location.leading_comments : []
        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)
        template_prefix_line_numbers = Prism::Merge::MagicCommentSupport.prefix_comment_line_numbers_for_comments(template_comments)
        dest_comments = dest_comments.reject { |comment| dest_prefix_comment_lines&.include?(comment.location.start_line) }
        last_skipped_template_line = nil
        if dest_prefix_comment_lines&.any?
          template_comments = template_comments.reject do |comment|
            if template_prefix_line_numbers.include?(comment.location.start_line)
              last_skipped_template_line = comment.location.start_line
              true
            end
          end
        end

        if node_preference == :template && template_comments.empty? && dest_comments.any?
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = merger.dest_analysis
        elsif node_preference == :template
          comment_source = :template
          leading_comments = template_comments
          comment_analysis = merger.template_analysis
        else
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = merger.dest_analysis
        end

        source_analysis = node_preference == :template ? merger.template_analysis : merger.dest_analysis
        source_node = node_preference == :template ? actual_template : actual_dest
        source_layout = merger.send(:node_body_layout_for, source_node, source_analysis)
        decision = MergeResult::DECISION_REPLACED
        template_inline_by_line = merger.send(:wrapper_inline_comment_entries_by_line, merger.template_analysis, actual_template)
        dest_inline_by_line = merger.send(:wrapper_inline_comment_entries_by_line, merger.dest_analysis, actual_dest)
        merged_body_lines = body_result ? body_result.lines.dup : []
        merged_body_metadata = body_result&.line_metadata&.dup || []

        prev_comment_line = comment_source == :template ? last_skipped_template_line : nil
        leading_comments.each do |comment|
          line_num = comment.location.start_line

          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              next if dest_prefix_comment_lines&.include?(blank_line_num)

              line = comment_analysis.line_at(blank_line_num)&.chomp || ""
              if comment_source == :template
                merger.result.add_line(line, decision: decision, template_line: blank_line_num)
              else
                merger.result.add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          line = comment_analysis.line_at(line_num)&.chomp || comment.slice.rstrip
          if comment_source == :template
            merger.result.add_line(line, decision: decision, template_line: line_num)
          else
            merger.result.add_line(line, decision: decision, dest_line: line_num)
          end

          prev_comment_line = line_num
        end

        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          merger.result.add_line("", decision: decision) if source_node.location.start_line > last_comment_line + 1
        end

        opening_line = source_layout.opening_line_text
        if node_preference == :template &&
            template_inline_by_line[actual_template.location.start_line].empty? &&
            !source_layout.body_starts_on_opening_line?
          dest_opening_inline = dest_inline_by_line[actual_dest.location.start_line]
          opening_line = merger.send(:append_inline_comment_entries, opening_line.to_s.chomp, dest_opening_inline) if dest_opening_inline.any?
        end
        if source_layout.body_starts_on_opening_line? && merged_body_lines.any?
          opening_line = "#{opening_line}#{merged_body_lines.shift}"
          merged_body_metadata.shift
        end
        merger.result.add_line(
          opening_line.chomp,
          decision: decision,
          template_line: node_preference == :template ? source_node.location.start_line : nil,
          dest_line: node_preference == :destination ? source_node.location.start_line : nil,
        )

        closing_body_line = nil
        if source_layout.body_ends_on_closing_line? && merged_body_lines.any?
          closing_body_line = merged_body_lines.pop
          merged_body_metadata.pop
        end

        merged_body_lines.each_with_index do |line, index|
          metadata = merged_body_metadata[index] || {}
          merger.result.add_line(
            line.chomp,
            decision: metadata[:decision] || decision,
            template_line: remap_body_line(metadata[:template_line], template_layout),
            dest_line: remap_body_line(metadata[:dest_line], dest_layout),
            comment: metadata[:comment],
          )
        end

        merger.send(:begin_node_plan_emitter).emit(
          template_node: actual_template,
          dest_node: actual_dest,
          node_preference: node_preference,
          decision: decision,
          template_inline_by_line: template_inline_by_line,
          dest_inline_by_line: dest_inline_by_line,
        )

        end_line = source_layout.closing_line_text
        if node_preference == :template && template_inline_by_line[actual_template.location.end_line].empty?
          dest_end_inline = dest_inline_by_line[actual_dest.location.end_line]
          end_line = merger.send(:append_inline_comment_entries, end_line.to_s.chomp, dest_end_inline) if dest_end_inline.any?
        end
        end_line = "#{closing_body_line}#{end_line}" if closing_body_line
        merger.result.add_line(
          end_line.chomp,
          decision: decision,
          template_line: node_preference == :template ? source_node.location.end_line : nil,
          dest_line: node_preference == :destination ? source_node.location.end_line : nil,
        )

        template_trailing_comments = merger.send(:external_trailing_comments_for, actual_template)
        dest_trailing_comments = merger.send(:external_trailing_comments_for, actual_dest)

        if node_preference == :template
          trailing_comments = template_trailing_comments.any? ? template_trailing_comments : dest_trailing_comments
          trailing_analysis = template_trailing_comments.any? ? merger.template_analysis : merger.dest_analysis
        else
          trailing_comments = dest_trailing_comments
          trailing_analysis = merger.dest_analysis
        end

        if trailing_comments.any?
          emitted_dest_line = merger.send(
            :emit_external_trailing_comments,
            merger.result,
            trailing_comments,
            source_node: trailing_analysis.equal?(merger.template_analysis) ? actual_template : actual_dest,
            analysis: trailing_analysis,
            source: trailing_analysis.equal?(merger.template_analysis) ? :template : :destination,
            decision: decision,
          )
          last_emitted_dest_line = emitted_dest_line if trailing_analysis.equal?(merger.dest_analysis)
          return {last_emitted_dest_line: last_emitted_dest_line}
        end

        trailing_line = source_node.location.end_line + 1
        trailing_content = source_analysis.line_at(trailing_line)
        if trailing_content && trailing_content.strip.empty?
          if node_preference == :template
            merger.result.add_line("", decision: decision, template_line: trailing_line)
          else
            merger.result.add_line("", decision: decision, dest_line: trailing_line)
          end
        end

        {last_emitted_dest_line: last_emitted_dest_line}
      end

      private

      def remap_body_line(body_line, layout)
        layout.source_line_for_body_line(body_line)
      end
    end
  end
end
