# frozen_string_literal: true

module Prism
  module Merge
    # Wrapper to represent freeze blocks as first-class nodes.
    # A freeze block is a section marked with freeze/unfreeze comment markers that
    # should be preserved from the destination during merges.
    #
    # While freeze blocks are delineated by comment markers, they are conceptually
    # different from CommentNode and do not inherit from it because:
    # - FreezeNode is a *structural directive* that contains code and/or comments
    # - CommentNode represents *pure documentation* with no structural significance
    # - FreezeNode can contain Ruby code nodes (methods, constants, etc.)
    # - CommentNode only contains comments
    # - Their signatures need different semantics for merge matching
    #
    # Freeze blocks can contain other nodes (methods, classes, etc.) and those
    # nodes remain as separate entities within the block for analysis purposes,
    # but the entire freeze block is treated as an atomic unit during merging.
    #
    # @example Freeze block with mixed content
    #   # prism-merge:freeze
    #   # Custom documentation
    #   CUSTOM_CONFIG = { key: "secret" }
    #   def custom_method
    #     # ...
    #   end
    #   # prism-merge:unfreeze
    class FreezeNode
      # Error raised when a freeze block has invalid structure
      class InvalidStructureError < StandardError
        attr_reader :start_line, :end_line, :unclosed_nodes

        def initialize(message, start_line: nil, end_line: nil, unclosed_nodes: [])
          super(message)
          @start_line = start_line
          @end_line = end_line
          @unclosed_nodes = unclosed_nodes
        end
      end

      attr_reader :start_line, :end_line, :content, :nodes, :start_marker, :end_marker

      # @param start_line [Integer] Line number of freeze marker
      # @param end_line [Integer] Line number of unfreeze marker
      # @param analysis [FileAnalysis] The file analysis containing this block
      # @param nodes [Array<Prism::Node>] Nodes fully contained within the freeze block
      # @param overlapping_nodes [Array<Prism::Node>] All nodes that overlap with freeze block (for validation)
      # @param start_marker [String, nil] The freeze start marker text
      # @param end_marker [String, nil] The freeze end marker text
      def initialize(start_line:, end_line:, analysis:, nodes: [], overlapping_nodes: nil, start_marker: nil, end_marker: nil)
        @start_line = start_line
        @end_line = end_line
        @analysis = analysis
        @nodes = nodes
        @overlapping_nodes = overlapping_nodes || nodes
        @start_marker = start_marker
        @end_marker = end_marker

        # Extract content for the entire block
        @content = (start_line..end_line).map { |ln| analysis.line_at(ln) }.join

        # Validate structure
        validate_structure!
      end

      # Returns a location-like object for compatibility with Prism nodes
      def location
        @location ||= Location.new(@start_line, @end_line)
      end

      # Returns the freeze block content
      def slice
        @content
      end

      # Simple location struct for compatibility
      Location = Struct.new(:start_line, :end_line) do
        def cover?(line)
          (start_line..end_line).cover?(line)
        end
      end

      # Returns a stable signature for this freeze block
      # Signature includes the normalized content to detect changes
      def signature
        normalized = (@start_line..@end_line).map do |ln|
          @analysis.normalized_line(ln)
        end.compact.join("\n")

        [:FreezeNode, normalized]
      end

      # Check if this is a freeze node (always true for FreezeNode)
      def freeze_node?
        true
      end

      # String representation for debugging
      def inspect
        "#<Prism::Merge::FreezeNode lines=#{@start_line}..#{@end_line} nodes=#{@nodes.length}>"
      end

      private

      # Validate that the freeze block has proper structure:
      # - All nodes must be either fully contained or fully outside
      # - No partial overlaps allowed (a node cannot start before and end inside, or vice versa)
      def validate_structure!
        unclosed = []

        # Check all overlapping nodes
        @overlapping_nodes.each do |node|
          node_start = node.location.start_line
          node_end = node.location.end_line

          # Check if node is fully contained (valid)
          fully_contained = node_start >= @start_line && node_end <= @end_line

          # Check if node completely encompasses the freeze block
          # This is valid for nodes that define a body scope where freeze blocks make sense:
          # - ClassNode, ModuleNode, SingletonClassNode (class/module definitions)
          # - CallNode with blocks (like RSpec describe/context blocks)
          # - DefNode (method definitions)
          # - LambdaNode (lambda/proc definitions)
          encompasses = node_start < @start_line && node_end > @end_line
          valid_encompass = encompasses && (
            node.is_a?(Prism::ClassNode) ||
            node.is_a?(Prism::ModuleNode) ||
            node.is_a?(Prism::SingletonClassNode) ||
            node.is_a?(Prism::DefNode) ||
            node.is_a?(Prism::LambdaNode) ||
            (node.is_a?(Prism::CallNode) && node.block) ||
            (node.is_a?(Prism::LocalVariableWriteNode) && node.value.is_a?(Prism::LambdaNode))
          )

          # Check if node partially overlaps (invalid - unclosed/incomplete structure)
          partially_overlaps = !fully_contained && !encompasses &&
            ((node_start < @start_line && node_end >= @start_line) ||
             (node_start <= @end_line && node_end > @end_line))

          # Invalid if: partial overlap OR if an unsupported node type encompasses the freeze block
          if partially_overlaps || (encompasses && !valid_encompass)
            unclosed << node
          end
        end

        return if unclosed.empty?

        # Build error message with details about unclosed/overlapping nodes
        node_descriptions = unclosed.map do |node|
          node_start = node.location.start_line
          node_end = node.location.end_line
          overlap_type = if node_start < @start_line
            "starts before freeze block (line #{node_start}) and ends inside (line #{node_end})"
          else
            "starts inside freeze block (line #{node_start}) and ends after (line #{node_end})"
          end
          "#{node.class.name.split("::").last} at lines #{node_start}-#{node_end} (#{overlap_type})"
        end.join(", ")

        raise InvalidStructureError.new(
          "Freeze block at lines #{@start_line}-#{@end_line} contains incomplete nodes: #{node_descriptions}. " \
            "A freeze block must fully contain all nodes within it, or be placed between nodes.",
          start_line: @start_line,
          end_line: @end_line,
          unclosed_nodes: unclosed,
        )
      end
    end
  end
end
