# frozen_string_literal: true

require "prism"

module Prism
  module Merge
    # Comprehensive metadata capture for a Ruby file being merged.
    # Tracks Prism parse result, line-to-node mapping, comment associations,
    # structural signatures, and sequential anchor lines for merge alignment.
    class FileAnalysis
      # Freeze block markers
      FREEZE_START = /#\s*kettle-dev:freeze/i
      FREEZE_END = /#\s*kettle-dev:unfreeze/i
      FREEZE_BLOCK = Regexp.new("(#{FREEZE_START.source}).*?(#{FREEZE_END.source})", Regexp::IGNORECASE | Regexp::MULTILINE)

      attr_reader :content, :parse_result, :lines, :statements, :freeze_blocks

      # @param content [String] Ruby source code to analyze
      # @param signature_generator [Proc, nil] Optional proc to generate node signatures
      def initialize(content, signature_generator: nil)
        @content = content
        @lines = content.lines
        @parse_result = Prism.parse(content)
        @statements = extract_statements
        @freeze_blocks = extract_freeze_blocks
        @signature_generator = signature_generator
        @line_to_node_map = nil
        @node_to_line_map = nil
        @comment_map = nil
      end

      # Check if parsing was successful
      # @return [Boolean]
      def valid?
        @parse_result.success?
      end

      # Get all top-level statement nodes
      # @return [Array<Prism::Node>]
      def extract_statements
        return [] unless valid?
        body = @parse_result.value.statements
        return [] unless body

        if body.is_a?(Prism::StatementsNode)
          body.body.compact
        else
          [body].compact
        end
      end

      # Extract freeze block information
      # @return [Array<Hash>] Array of freeze block metadata
      def extract_freeze_blocks
        return [] unless content.match?(FREEZE_START)

        blocks = []
        content.to_enum(:scan, FREEZE_BLOCK).each do
          match = Regexp.last_match
          next unless match

          start_idx = match.begin(0)
          end_idx = match.end(0)
          segment = match[0]
          start_line = content[0...start_idx].count("\n") + 1
          end_line = content[0...end_idx].count("\n") + 1

          blocks << {
            range: start_idx...end_idx,
            line_range: start_line..end_line,
            text: segment,
            start_marker: segment&.lines&.first&.strip,
          }
        end

        blocks
      end

      # Build mapping from line numbers to AST nodes
      # @return [Hash<Integer, Array<Prism::Node>>] Line number => nodes on that line
      def line_to_node_map
        @line_to_node_map ||= build_line_to_node_map
      end

      # Build mapping from nodes to line ranges
      # @return [Hash<Prism::Node, Range>] Node => line range
      def node_to_line_map
        @node_to_line_map ||= build_node_to_line_map
      end

      # Get nodes with their associated comments and metadata
      # @return [Array<Hash>] Array of node info hashes
      def nodes_with_comments
        @nodes_with_comments ||= extract_nodes_with_comments
      end

      # Get comment map by line number
      # @return [Hash<Integer, Array<Prism::Comment>>] Line number => comments
      def comment_map
        @comment_map ||= build_comment_map
      end

      # Get structural signature for a statement at given index
      # @param index [Integer] Statement index
      # @return [Array, nil] Signature array
      def signature_at(index)
        return if index < 0 || index >= statements.length
        generate_signature(statements[index])
      end

      # Generate signature for a node
      # @param node [Prism::Node] Node to generate signature for
      # @return [Array, nil] Signature array
      def generate_signature(node)
        if @signature_generator
          @signature_generator.call(node)
        else
          default_signature(node)
        end
      end

      # Check if a line is within a freeze block
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def in_freeze_block?(line_num)
        freeze_blocks.any? { |block| block[:line_range].cover?(line_num) }
      end

      # Get the freeze block containing the given line, if any
      # @param line_num [Integer] 1-based line number
      # @return [Hash, nil] Freeze block metadata or nil
      def freeze_block_at(line_num)
        freeze_blocks.find { |block| block[:line_range].cover?(line_num) }
      end

      # Get normalized line content (stripped)
      # @param line_num [Integer] 1-based line number
      # @return [String, nil]
      def normalized_line(line_num)
        return if line_num < 1 || line_num > lines.length
        lines[line_num - 1].strip
      end

      # Get raw line content
      # @param line_num [Integer] 1-based line number
      # @return [String, nil]
      def line_at(line_num)
        return if line_num < 1 || line_num > lines.length
        lines[line_num - 1]
      end

      private

      def build_line_to_node_map
        map = Hash.new { |h, k| h[k] = [] }
        return map unless valid?

        statements.each do |node|
          start_line = node.location.start_line
          end_line = node.location.end_line
          (start_line..end_line).each do |line_num|
            map[line_num] << node
          end
        end

        map
      end

      def build_node_to_line_map
        map = {}
        return map unless valid?

        statements.each do |node|
          map[node] = node.location.start_line..node.location.end_line
        end

        map
      end

      def extract_nodes_with_comments
        return [] unless valid?

        statements.map.with_index do |stmt, idx|
          prev_stmt = (idx > 0) ? statements[idx - 1] : nil
          body_node = @parse_result.value.statements

          {
            node: stmt,
            index: idx,
            leading_comments: find_leading_comments(stmt, prev_stmt, body_node),
            inline_comments: inline_comments_for_node(stmt),
            signature: generate_signature(stmt),
            line_range: stmt.location.start_line..stmt.location.end_line,
          }
        end
      end

      def find_leading_comments(current_stmt, prev_stmt, body_node)
        start_line = prev_stmt ? prev_stmt.location.end_line : 0
        end_line = current_stmt.location.start_line

        # Find all comments in the range
        candidates = @parse_result.comments.select do |comment|
          comment.location.start_line > start_line &&
            comment.location.start_line < end_line
        end

        # Only include comments that are immediately adjacent to the statement
        # (no blank lines between the comment and the statement)
        adjacent_comments = []
        expected_line = end_line - 1

        candidates.reverse_each do |comment|
          comment_line = comment.location.start_line

          # Only include if this comment is immediately adjacent (no gaps)
          if comment_line == expected_line
            adjacent_comments.unshift(comment)
            expected_line = comment_line - 1
          else
            # Gap found (blank line or code), stop looking
            break
          end
        end

        adjacent_comments
      end

      def inline_comments_for_node(stmt)
        @parse_result.comments.select do |comment|
          # Check if comment is on the same line as the start of the statement
          # and appears after the statement text begins
          comment.location.start_line == stmt.location.start_line &&
            comment.location.start_offset > stmt.location.start_offset
        end
      end

      def build_comment_map
        map = Hash.new { |h, k| h[k] = [] }
        return map unless valid?

        @parse_result.comments.each do |comment|
          line = comment.location.start_line
          map[line] << comment
        end

        map
      end

      # Default signature generation
      def default_signature(node)
        return [:nil] unless node

        # For conditional nodes, signature should be based on the condition only,
        # not the body, so conditionals with same condition but different bodies
        # are recognized as matching
        case node
        when Prism::IfNode, Prism::UnlessNode
          condition_slice = node.predicate&.slice || ""
          [node.class.name.split("::").last.to_sym, condition_slice]
        when Prism::ConstantWriteNode, Prism::GlobalVariableWriteNode,
             Prism::InstanceVariableWriteNode, Prism::ClassVariableWriteNode,
             Prism::LocalVariableWriteNode
          # For variable/constant assignments, signature based on name only,
          # not the value, so assignments with same name but different values
          # are recognized as matching
          name = node.respond_to?(:name) ? node.name.to_s : node.slice.split("=").first.strip
          [node.class.name.split("::").last.to_sym, name]
        else
          [node.class.name.split("::").last.to_sym, node.slice]
        end
      end
    end
  end
end
