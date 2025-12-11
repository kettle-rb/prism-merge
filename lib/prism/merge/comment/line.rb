# frozen_string_literal: true

require "ast/merge/comment"

module Prism
  module Merge
    module Comment
      # Ruby-specific comment line with magic comment detection.
      #
      # Extends the generic `Ast::Merge::Comment::Line` with Ruby-specific
      # features like detection of magic comments (frozen_string_literal,
      # encoding, etc.).
      #
      # @example
      #   line = Line.new(text: "# frozen_string_literal: true", line_number: 1)
      #   line.magic_comment? #=> true
      #   line.magic_comment_type #=> :frozen_string_literal
      #
      class Line < Ast::Merge::Comment::Line
        # Ruby magic comment patterns
        MAGIC_COMMENT_PATTERNS = {
          frozen_string_literal: /^frozen_string_literal:\s*(true|false)$/i,
          encoding: /^(encoding|coding):\s*\S+$/i,
          warn_indent: /^warn_indent:\s*(true|false)$/i,
          shareable_constant_value: /^shareable_constant_value:\s*\S+$/i,
        }.freeze

        # Initialize a new Ruby comment Line.
        #
        # Always uses hash_comment style for Ruby.
        #
        # @param text [String] The full comment text including `#`
        # @param line_number [Integer] The 1-based line number
        def initialize(text:, line_number:)
          super(text: text, line_number: line_number, style: :hash_comment)
        end

        # Check if this is a Ruby magic comment.
        #
        # Magic comments are special comments that affect Ruby's behavior:
        # - `# frozen_string_literal: true/false`
        # - `# encoding: UTF-8`
        # - `# coding: UTF-8`
        # - `# warn_indent: true/false`
        # - `# shareable_constant_value: literal/...`
        #
        # @return [Boolean] true if this is a magic comment
        def magic_comment?
          MAGIC_COMMENT_PATTERNS.any? { |_, pattern| content.strip.match?(pattern) }
        end

        # Get the type of magic comment.
        #
        # @return [Symbol, nil] The magic comment type, or nil if not a magic comment
        def magic_comment_type
          MAGIC_COMMENT_PATTERNS.each do |type, pattern|
            return type if content.strip.match?(pattern)
          end
          nil
        end

        # Get the value of a magic comment.
        #
        # @return [String, nil] The magic comment value, or nil if not a magic comment
        def magic_comment_value
          stripped = content.strip
          MAGIC_COMMENT_PATTERNS.each do |_, pattern|
            if stripped.match?(pattern)
              # Extract the value after the colon
              return stripped.split(":", 2).last&.strip
            end
          end
          nil
        end

        # @return [String] Human-readable representation
        def inspect
          magic = magic_comment? ? " magic=#{magic_comment_type}" : ""
          "#<Prism::Merge::Comment::Line line=#{line_number}#{magic} #{text.inspect}>"
        end
      end
    end
  end
end
