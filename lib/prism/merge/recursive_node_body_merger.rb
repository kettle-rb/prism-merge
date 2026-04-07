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

        # When the gemspec block uses different variable names (e.g. |gem| vs |spec|),
        # rewrite the non-preferred side's body text so that dest-only or template-only
        # nodes emit with the correct receiver.  Uses AST-directed byte-offset
        # replacement — no regular expressions.
        template_var = merger.template_analysis.respond_to?(:gemspec_block_var) ? merger.template_analysis.gemspec_block_var : nil
        dest_var = merger.dest_analysis.respond_to?(:gemspec_block_var) ? merger.dest_analysis.gemspec_block_var : nil
        preferred_var = nil
        if template_var && dest_var && template_var != dest_var
          preferred_var = (merger.preference == :destination) ? dest_var : template_var
          if dest_var != preferred_var
            dest_body = GemspecVarRenamer.rename(dest_body, old_var: dest_var, new_var: preferred_var)
          end
          if template_var != preferred_var
            template_body = GemspecVarRenamer.rename(template_body, old_var: template_var, new_var: preferred_var)
          end
        end

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
          # Thread gemspec block-variable names so inner FileAnalysis objects can normalise
          # assignment signatures even when the Gem::Specification.new wrapper is absent
          # from the extracted body text (auto-detection cannot fire without the wrapper).
          # When renaming was applied above, both sides now use preferred_var.
          template_gemspec_block_var: preferred_var || template_var,
          dest_gemspec_block_var: preferred_var || dest_var,
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
        dest_claimed = merger.dest_analysis.respond_to?(:claimed_lines) ? merger.dest_analysis.claimed_lines : Set.new
        template_claimed = merger.template_analysis.respond_to?(:claimed_lines) ? merger.template_analysis.claimed_lines : Set.new
        dest_comments = dest_comments.reject { |comment|
          ln = comment.location.start_line
          dest_prefix_comment_lines&.include?(ln) || dest_claimed.include?(ln)
        }
        last_skipped_template_line = nil
        if dest_prefix_comment_lines&.any? || template_claimed.any?
          template_comments = template_comments.reject do |comment|
            ln = comment.location.start_line
            if template_prefix_line_numbers.include?(ln) || template_claimed.include?(ln)
              last_skipped_template_line = ln
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

        source_analysis = (node_preference == :template) ? merger.template_analysis : merger.dest_analysis
        source_node = (node_preference == :template) ? actual_template : actual_dest
        source_layout = merger.send(:node_body_layout_for, source_node, source_analysis)
        decision = MergeResult::DECISION_REPLACED
        template_inline_by_line = merger.send(:wrapper_inline_comment_entries_by_line, merger.template_analysis, actual_template)
        dest_inline_by_line = merger.send(:wrapper_inline_comment_entries_by_line, merger.dest_analysis, actual_dest)
        merged_body_lines = body_result ? body_result.lines.dup : []
        merged_body_metadata = body_result&.line_metadata&.dup || []

        prev_comment_line = (comment_source == :template) ? last_skipped_template_line : nil
        merger.send(
          :emit_leading_comments,
          merger.result,
          leading_comments,
          analysis: comment_analysis,
          source: comment_source,
          decision: decision,
          prev_comment_line: prev_comment_line,
        )

        if comment_source == :destination && leading_comments.any?
          last_emitted_dest_line = leading_comments.last.location.start_line
        end

        if leading_comments.any?
          emitted_gap_line = merger.send(
            :emit_blank_lines_between,
            merger.result,
            last_comment_line: leading_comments.last.location.start_line,
            next_content_line: source_node.location.start_line,
            analysis: comment_analysis,
            source: comment_source,
            decision: decision,
          )
          last_emitted_dest_line = emitted_gap_line if comment_source == :destination && emitted_gap_line
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
          template_line: (node_preference == :template) ? source_node.location.start_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.start_line : nil,
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
          template_line: (node_preference == :template) ? source_node.location.end_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.end_line : nil,
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
        emitted_trailing_gap_line = emit_trailing_layout_gap_lines(
          analysis: source_analysis,
          owner: source_node,
          source: (node_preference == :template) ? :template : :destination,
          decision: decision,
        )

        if emitted_trailing_gap_line
          last_emitted_dest_line = emitted_trailing_gap_line if node_preference == :destination
        elsif trailing_content && trailing_content.strip.empty?
          if node_preference == :template
            merger.result.add_line("", decision: decision, template_line: trailing_line)
          else
            merger.result.add_line("", decision: decision, dest_line: trailing_line)
            last_emitted_dest_line = trailing_line
          end
        end

        {last_emitted_dest_line: last_emitted_dest_line}
      end

      private

      def emit_trailing_layout_gap_lines(analysis:, owner:, source:, decision:)
        return unless analysis.respond_to?(:layout_attachment_for)

        attachment = analysis.layout_attachment_for(owner)
        gap = attachment&.trailing_gap
        return unless gap
        return unless gap.controls_output_for?(owner)

        last_emitted_line = nil

        (gap.start_line..gap.end_line).each do |line_num|
          line = analysis.line_at(line_num).to_s.chomp
          next unless line.strip.empty?

          if source == :template
            merger.result.add_line(line, decision: decision, template_line: line_num)
          else
            merger.result.add_line(line, decision: decision, dest_line: line_num)
          end

          last_emitted_line = line_num
        end

        last_emitted_line
      end

      def remap_body_line(body_line, layout)
        layout.source_line_for_body_line(body_line)
      end
    end
  end
end
