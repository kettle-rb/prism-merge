# frozen_string_literal: true

module Prism
  module Merge
    class CommentOnlyFileMerger
      attr_reader :merger, :comment_only_prefix_lines

      def initialize(merger:)
        @merger = merger
        @comment_only_prefix_lines = {
          template: Set.new,
          destination: Set.new,
        }
      end

      def comment_only_file?(analysis)
        statements = analysis.statements
        return false if statements.nil? || statements.empty?

        statements.all? do |statement|
          statement.is_a?(Ast::Merge::Comment::Empty) ||
            statement.is_a?(Ast::Merge::Comment::Block) ||
            statement.is_a?(Ast::Merge::Comment::Line)
        end
      end

      def merge
        @comment_only_prefix_lines = {
          template: Set.new,
          destination: Set.new,
        }

        template_lines = merger.template_content.lines.map(&:chomp)
        dest_lines = merger.dest_content.lines.map(&:chomp)

        emit_comment_only_prefix_lines(template_lines, dest_lines)

        template_nodes = Comment::Parser.parse(template_lines)
        dest_nodes = Comment::Parser.parse(dest_lines)
        dest_indices_by_signature = build_comment_indices_map(dest_nodes)
        output_template_signatures = Set.new
        matched_dest_indices = Set.new

        template_nodes.each do |template_node|
          template_signature = template_node.respond_to?(:signature) ? template_node.signature : nil
          next if template_signature && output_template_signatures.include?(template_signature)

          dest_index = find_first_unmatched_index(dest_indices_by_signature, template_signature, matched_dest_indices)

          if dest_index
            dest_node = dest_nodes[dest_index]
            matched_dest_indices << dest_index
            output_template_signatures << template_signature if template_signature

            if merger.send(:default_preference) == :template
              add_comment_node_to_result(template_node, :template)
            else
              add_comment_node_to_result(dest_node, :destination)
            end
          elsif merger.add_template_only_nodes ||
              (merger.send(:default_preference) == :template && template_node.respond_to?(:magic_comment?) && template_node.magic_comment?)
            add_comment_node_to_result(template_node, :template)
            output_template_signatures << template_signature if template_signature
          end
        end

        if merger.send(:default_preference) == :destination
          dest_nodes.each_with_index do |dest_node, index|
            next if matched_dest_indices.include?(index)

            add_comment_node_to_result(dest_node, :destination)
          end
        end

        merger.result
      end

      private

      def build_comment_indices_map(nodes)
        nodes.each_with_index.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(node, index), map|
          signature = node.respond_to?(:signature) ? node.signature : nil
          map[signature] << index if signature
        end
      end

      def find_first_unmatched_index(indices_map, signature, matched_indices)
        return unless signature

        indices = indices_map[signature]
        return unless indices

        indices.find { |index| !matched_indices.include?(index) }
      end

      def add_comment_node_to_result(node, source)
        decision = source == :template ? MergeResult::DECISION_KEPT_TEMPLATE : MergeResult::DECISION_KEPT_DEST
        suppressed_lines = comment_only_prefix_lines.fetch(source, Set.new)

        content = if node.respond_to?(:text)
          node.text
        elsif node.respond_to?(:content)
          node.content
        else
          node.to_s
        end

        if node.respond_to?(:children) && node.children.any?
          node.children.each do |child|
            child_content = child.respond_to?(:text) ? child.text : child.to_s
            line_num = child.respond_to?(:line_number) ? child.line_number : nil
            next if line_num && suppressed_lines.include?(line_num)

            if source == :template
              merger.result.add_line(child_content, decision: decision, template_line: line_num)
            else
              merger.result.add_line(child_content, decision: decision, dest_line: line_num)
            end
          end
        else
          line_num = node.respond_to?(:line_number) ? node.line_number : nil
          return if line_num && suppressed_lines.include?(line_num)

          if source == :template
            merger.result.add_line(content, decision: decision, template_line: line_num)
          else
            merger.result.add_line(content, decision: decision, dest_line: line_num)
          end
        end
      end

      def emit_comment_only_prefix_lines(template_lines, dest_lines)
        dest_prefix = comment_only_prefix_lines_for(dest_lines)
        return if dest_prefix[:entries].empty?

        dest_prefix[:entries].each do |entry|
          merger.result.add_line(entry[:text], decision: MergeResult::DECISION_KEPT_DEST, dest_line: entry[:line_num])
        end
        dest_prefix[:suppressed_line_nums].each { |line_num| comment_only_prefix_lines[:destination] << line_num }

        template_prefix = comment_only_prefix_lines_for(template_lines)
        template_prefix[:suppressed_line_nums].each { |line_num| comment_only_prefix_lines[:template] << line_num }
      end

      def comment_only_prefix_lines_for(lines)
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

      def ruby_magic_comment_line_type(line)
        text = line.sub(/\A#\s*/, "").strip
        Comment::Line::MAGIC_COMMENT_PATTERNS.each do |type, pattern|
          return type if text.match?(pattern)
        end

        nil
      end
    end
  end
end
