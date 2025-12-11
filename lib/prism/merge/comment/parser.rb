# frozen_string_literal: true

require "ast/merge/comment"
require_relative "line"
require_relative "block"

module Prism
  module Merge
    module Comment
      # Ruby-specific comment parser.
      #
      # Produces `Prism::Merge::Comment::Line` and `Prism::Merge::Comment::Block`
      # nodes instead of the generic `Ast::Merge::Comment::*` classes, enabling
      # Ruby-specific features like magic comment detection.
      #
      # @example
      #   lines = ["# frozen_string_literal: true", "", "# A comment"]
      #   nodes = Parser.parse(lines)
      #   nodes.first.contains_magic_comment? #=> true
      #
      class Parser
        # @return [Array<String>] The source lines
        attr_reader :lines

        # Initialize a new Ruby comment Parser.
        #
        # @param lines [Array<String>] Source lines
        def initialize(lines)
          @lines = lines || []
        end

        # Parse the lines into Ruby-specific comment AST.
        #
        # @return [Array<Ast::Merge::AstNode>] Parsed nodes
        def parse
          return [] if lines.empty?

          nodes = []
          current_block = []

          lines.each_with_index do |line, idx|
            line_number = idx + 1
            stripped = line.to_s.rstrip

            if stripped.empty?
              # Blank line - flush current block and add Empty
              if current_block.any?
                nodes << build_block(current_block)
                current_block = []
              end
              nodes << Ast::Merge::Comment::Empty.new(line_number: line_number, text: line.to_s)
            elsif stripped.start_with?("#")
              # Ruby comment line
              current_block << Line.new(
                text: stripped,
                line_number: line_number
              )
            else
              # Non-comment content (shouldn't happen in comment-only files)
              if current_block.any?
                nodes << build_block(current_block)
                current_block = []
              end
              # Add as generic line
              nodes << Ast::Merge::Comment::Line.new(
                text: stripped,
                line_number: line_number,
                style: :hash_comment
              )
            end
          end

          # Flush remaining block
          if current_block.any?
            nodes << build_block(current_block)
          end

          nodes
        end

        # Class method for convenient one-shot parsing.
        #
        # @param lines [Array<String>] Source lines
        # @return [Array<Ast::Merge::AstNode>] Parsed nodes
        def self.parse(lines)
          new(lines).parse
        end

        private

        # Build a Block from accumulated comment lines.
        #
        # @param comment_lines [Array<Line>] The comment lines
        # @return [Block] Block containing the lines
        def build_block(comment_lines)
          Block.new(children: comment_lines)
        end
      end
    end
  end
end
