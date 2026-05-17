# frozen_string_literal: true

module Markdown
  module Merge
    # Represents a frozen block of Markdown content that should be preserved during merges.
    #
    # Freeze blocks are marked with HTML comments:
    #   <!-- markdown-merge:freeze -->
    #   ... frozen content ...
    #   <!-- markdown-merge:unfreeze -->
    #
    # Content within freeze blocks is preserved exactly as-is during merge operations,
    # preventing automated tools from modifying manually-curated sections.
    #
    # @example Basic freeze block
    #   <!-- markdown-merge:freeze -->
    #   ## Custom Section
    #   This content will not be modified by merge operations.
    #   <!-- markdown-merge:unfreeze -->
    #
    # @example Freeze block with reason
    #   <!-- markdown-merge:freeze Manual TOC -->
    #   ## Table of Contents
    #   - [Introduction](#introduction)
    #   - [Usage](#usage)
    #   <!-- markdown-merge:unfreeze -->
    #
    # @see Ast::Merge::FreezeNodeBase Base class
    class FreezeNode < Ast::Merge::FreezeNodeBase
      # Initialize a new FreezeNode
      #
      # @param start_line [Integer] Starting line number (1-indexed)
      # @param end_line [Integer] Ending line number (1-indexed)
      # @param content [String] Raw Markdown content within the block
      # @param start_marker [String] The freeze marker comment
      # @param end_marker [String] The unfreeze marker comment
      # @param nodes [Array] Parsed nodes within the block
      # @param reason [String, nil] Optional reason extracted from marker
      def initialize(start_line:, end_line:, content:, start_marker:, end_marker:, nodes: [], reason: nil)
        # Let the base class handle reason extraction via pattern_for
        super(
          start_line: start_line,
          end_line: end_line,
          content: content,
          nodes: nodes,
          start_marker: start_marker,
          end_marker: end_marker,
          pattern_type: :html_comment,
          reason: reason
        )
      end

      # Generate a signature for matching this freeze block
      #
      # Signatures are based on the normalized content, allowing freeze blocks
      # with the same content to be matched across files.
      #
      # @return [Array<Symbol, String>] Signature array [:freeze_block, content_digest]
      def signature
        [:freeze_block, Digest::SHA256.hexdigest(content.strip)[0, 16]]
      end

      # Get the full text including markers
      #
      # @return [String] Complete freeze block with markers
      def full_text
        "#{start_marker}\n#{content}\n#{end_marker}"
      end

      # Get line count of the freeze block
      #
      # @return [Integer] Number of lines
      def line_count
        end_line - start_line + 1
      end

      # Check if block contains a specific node type
      #
      # @param type [Symbol] Node type to check for (e.g., :heading, :paragraph)
      # @return [Boolean] True if block contains the node type
      def contains_type?(type)
        nodes.any? { |node| node.type == type }
      end

      # String representation for debugging
      #
      # @return [String] Debug representation
      def inspect
        "#<#{self.class.name} lines=#{start_line}..#{end_line} nodes=#{nodes.size} reason=#{reason.inspect}>"
      end
    end
  end
end
