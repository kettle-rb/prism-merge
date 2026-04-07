# frozen_string_literal: true

module Prism
  module Merge
    class TopLevelMergeRunner
      include ::Ast::Merge::TrailingGroups::DestIterate

      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def merge
        return merger.send(:comment_only_file_merger).merge if comment_only_merge?

        template_by_signature = merger.send(:build_signature_map, merger.template_analysis)
        dest_by_signature = merger.send(:build_signature_map, merger.dest_analysis)
        prepare_comment_augmenters!(template_by_signature: template_by_signature, dest_by_signature: dest_by_signature)
        consumed_template_indices = Set.new
        sig_cursor = Hash.new(0)
        output_dest_line_ranges = []
        last_output_dest_line = merger.send(:emit_dest_prefix_lines, merger.result, merger.dest_analysis)

        # Pre-compute position-aware trailing groups for template-only nodes.
        dest_sigs = ::Set.new(dest_by_signature.keys)

        # Collect signatures from ALL depths of the destination AST so that
        # template-only nodes whose content already exists inside a destination
        # block (e.g. eval_gemfile inside an `if`) are recognized as "moved"
        # rather than duplicated.
        @deep_dest_sigs = collect_deep_signatures(merger.dest_analysis)

        trailing_groups, _matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: merger.template_analysis.statements,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { merger.template_analysis.generate_signature(node) },
          add_template_only_nodes: merger.add_template_only_nodes,
        )

        # Emit template-only nodes that precede the first matched template node
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
        end

        merger.dest_analysis.statements.each do |dest_node|
          last_output_dest_line = process_dest_node(
            dest_node: dest_node,
            template_by_signature: template_by_signature,
            consumed_template_indices: consumed_template_indices,
            sig_cursor: sig_cursor,
            output_dest_line_ranges: output_dest_line_ranges,
            last_output_dest_line: last_output_dest_line,
            trailing_groups: trailing_groups,
          )
        end

        # Safety net: emit any trailing groups whose anchor was never consumed
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices,
        ) do |info|
          merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
        end

        emit_dest_postlude_lines(last_output_dest_line)

        merger.result
      end

      private

      # Override the ast-merge hook so template-only nodes that exist at a
      # deeper level in the destination AST are treated as "moved" matches
      # rather than true template-only additions.
      def trailing_group_node_matched?(_node, signature)
        return false unless signature
        return false unless @deep_dest_sigs

        @deep_dest_sigs.include?(signature)
      end

      def comment_only_merge?
        merger.comment_only_file?(merger.template_analysis) && merger.comment_only_file?(merger.dest_analysis)
      end

      def prepare_comment_augmenters!(template_by_signature:, dest_by_signature:)
        retained = retained_owner_plan(template_by_signature: template_by_signature, dest_by_signature: dest_by_signature)

        merger.instance_variable_set(:@template_retained_owners, retained[:template])
        merger.instance_variable_set(:@dest_retained_owners, retained[:destination])
        merger.instance_variable_set(
          :@template_comment_augmenter,
          merger.template_analysis.comment_augmenter(owners: retained[:template]),
        )
        merger.instance_variable_set(
          :@dest_comment_augmenter,
          merger.dest_analysis.comment_augmenter(owners: retained[:destination]),
        )
      end

      def retained_owner_plan(template_by_signature:, dest_by_signature:)
        matched_template_indices = Set.new
        retained_dest_indices = Set.new
        sig_cursor = Hash.new(0)

        merger.dest_analysis.statements.each_with_index do |dest_node, dest_index|
          dest_signature = merger.dest_analysis.generate_signature(dest_node)
          next unless dest_signature && template_by_signature.key?(dest_signature)

          template_info, cursor = next_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor,
          )
          next unless template_info

          matched_template_indices << template_info[:index]
          retained_dest_indices << dest_index
          sig_cursor[dest_signature] = cursor + 1
        end

        merger.dest_analysis.statements.each_with_index do |_dest_node, dest_index|
          next if retained_dest_indices.include?(dest_index)
          next if merger.remove_template_missing_nodes

          retained_dest_indices << dest_index
        end

        template_retained = merger.template_analysis.statements.each_with_index.filter_map do |template_node, template_index|
          next template_node if matched_template_indices.include?(template_index)
          next template_node if merger.add_template_only_nodes

          nil
        end

        destination_retained = merger.dest_analysis.statements.each_with_index.filter_map do |dest_node, dest_index|
          dest_node if retained_dest_indices.include?(dest_index)
        end

        {
          template: template_retained,
          destination: destination_retained,
        }
      end

      def process_dest_node(dest_node:, template_by_signature:, consumed_template_indices:, sig_cursor:, output_dest_line_ranges:, last_output_dest_line:, trailing_groups: {})
        node_range = node_offset_range(dest_node)
        return last_output_dest_line if already_output?(node_range, output_dest_line_ranges)

        dest_signature = merger.dest_analysis.generate_signature(dest_node)
        last_output_dest_line = merger.send(:emit_dest_gap_lines, merger.result, merger.dest_analysis, last_output_dest_line, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis
        advance_dest_output = true

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

            # Emit template-only nodes that follow this matched template node
            matched_template_index = template_info[:index]
            group = trailing_groups[matched_template_index]
            group&.each do |info|
              next if consumed_template_indices.include?(info[:index])

              merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
              consumed_template_indices << info[:index]
            end
          else
            if merger.remove_template_missing_nodes
              emission = merger.send(:emit_removed_destination_node_comments, merger.result, dest_node, merger.dest_analysis)
              last_output_dest_line = emission_last_output(last_output_dest_line, emission)
              advance_dest_output = advance_dest_output?(emission)
            else
              emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
              last_output_dest_line = emission_last_output(last_output_dest_line, emission)
            end
            output_dest_line_ranges << node_range
          end
        else
          if merger.remove_template_missing_nodes
            emission = merger.send(:emit_removed_destination_node_comments, merger.result, dest_node, merger.dest_analysis)
            last_output_dest_line = emission_last_output(last_output_dest_line, emission)
            advance_dest_output = advance_dest_output?(emission)
          else
            emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
            last_output_dest_line = emission_last_output(last_output_dest_line, emission)
          end
          output_dest_line_ranges << node_range
        end

        advance_last_output_dest_line(
          last_output_dest_line: last_output_dest_line,
          dest_node: dest_node,
          output_node: output_node,
          output_analysis: output_analysis,
          advance_dest_output: advance_dest_output,
          preserve_trailing_blank_line_progress: emission&.fetch(:preserve_trailing_blank_line_progress, false),
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
          preserve_trailing_blank_line_progress: true,
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
          emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, emission),
          output_node: output_node,
          output_analysis: output_analysis,
          preserve_trailing_blank_line_progress: emission&.fetch(:preserve_trailing_blank_line_progress, false),
        }
      end

      def emission_last_output(last_output_dest_line, emission)
        emitted_dest_line = emission&.dig(:last_emitted_dest_line)
        return last_output_dest_line unless emitted_dest_line

        [last_output_dest_line, emitted_dest_line].max
      end

      def advance_last_output_dest_line(last_output_dest_line:, dest_node:, output_node:, output_analysis:, advance_dest_output: true, preserve_trailing_blank_line_progress: false)
        return last_output_dest_line unless advance_dest_output

        updated_last_output_dest_line = [last_output_dest_line, dest_node.location.end_line].max

        return updated_last_output_dest_line unless preserve_trailing_blank_line_progress

        actual_output_end = unwrap_node(output_node).location.end_line
        trailing_line_num = actual_output_end + 1
        trailing_content = output_analysis.line_at(trailing_line_num)
        return updated_last_output_dest_line unless trailing_content && trailing_content.strip.empty?

        trailing_dest_line = dest_node.location.end_line + 1
        dest_trailing = merger.dest_analysis.line_at(trailing_dest_line)
        return updated_last_output_dest_line unless dest_trailing && dest_trailing.strip.empty?

        [updated_last_output_dest_line, trailing_dest_line].max
      end

      def advance_dest_output?(emission)
        !emission&.fetch(:emitted_removed_owner_comments, false)
      end

      def emit_dest_postlude_lines(last_output_dest_line)
        postlude_gap = merger.dest_analysis.layout_augmenter.postlude_gap
        if postlude_gap
          emit_dest_blank_lines(([postlude_gap.start_line, last_output_dest_line + 1].max)..postlude_gap.end_line)
          return
        end

        remaining_line_range = (last_output_dest_line + 1)..merger.dest_analysis.lines.length
        emit_dest_blank_lines(remaining_line_range)
      end

      def emit_dest_blank_lines(line_range)
        return if line_range.begin > line_range.end

        line_range.each do |line_num|
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

      # Recursively collect signatures from all depths of the destination AST.
      # This enables "moved node" detection: a template top-level node whose
      # signature exists inside a destination block (e.g. inside an `if`)
      # should not be re-added as template-only.
      #
      # Only descends into body/statements of compound nodes (if, unless,
      # begin, blocks, etc.) — not into method definitions or class bodies
      # where the same call name would have different semantics.
      def collect_deep_signatures(analysis)
        sigs = ::Set.new
        analysis.statements.each do |node|
          collect_nested_signatures(node, analysis, sigs, depth: 0)
        end
        sigs
      end

      # Walk a single node's subtree collecting signatures from nested statements.
      # Limits recursion to compound statement nodes where a "moved" statement
      # is likely (conditionals, begin/rescue, blocks on method calls).
      def collect_nested_signatures(node, analysis, sigs, depth:)
        actual = unwrap_node(node)
        sig = analysis.generate_signature(actual)
        sigs << sig if sig && depth > 0

        children = nested_statement_children(actual)
        children.each do |child|
          collect_nested_signatures(child, analysis, sigs, depth: depth + 1)
        end
      end

      # Extract the immediate statement children of compound nodes where
      # a statement might have been "moved" from top-level into a block.
      def nested_statement_children(node)
        children = []
        case node
        when Prism::IfNode, Prism::UnlessNode
          children.concat(extract_body(node.statements))
          subsequent = node.respond_to?(:subsequent) ? node.subsequent : node.consequent
          children.concat(extract_body(subsequent.statements)) if subsequent.respond_to?(:statements)
          children.concat(nested_statement_children(subsequent)) if subsequent.is_a?(Prism::IfNode) || subsequent.is_a?(Prism::ElseNode)
        when Prism::ElseNode
          children.concat(extract_body(node.statements))
        when Prism::BeginNode
          children.concat(extract_body(node.statements))
          children.concat(extract_body(node.rescue_clause.statements)) if node.rescue_clause&.respond_to?(:statements)
          children.concat(extract_body(node.else_clause.statements)) if node.else_clause&.respond_to?(:statements)
          children.concat(extract_body(node.ensure_clause.statements)) if node.ensure_clause&.respond_to?(:statements)
        when Prism::CallNode
          if node.block.is_a?(Prism::BlockNode)
            children.concat(extract_body(node.block.body))
          end
        end
        children
      end

      def extract_body(statements_node)
        return [] unless statements_node

        if statements_node.is_a?(Prism::StatementsNode)
          statements_node.body.compact
        elsif statements_node.respond_to?(:body)
          Array(statements_node.body).compact
        else
          []
        end
      end
    end
  end
end
