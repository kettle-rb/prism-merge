# frozen_string_literal: true

module Prism
  module Merge
    # Wrapper for AST nodes that have an unbalanced or inline nocov marker.
    #
    # Analogous to Ast::Merge::NodeTyping::FrozenWrapper, but for nocov.
    #
    # An unbalanced nocov marker is a `# :nocov:` that appears in a node's leading
    # or trailing comments without a matching close marker at the same level.
    # Example: a method with a trailing `# :nocov:` inline comment.
    #
    # NoCovWrapper wraps the node so merge code can detect and handle it via
    # `is_a?(Prism::Merge::NoCovWrapper)` checks.
    #
    # The wrapped node's structural signature is still used for matching (like
    # FrozenWrapper), not a content-based signature.
    class NoCovWrapper
      include Ast::Merge::BlockDirective

      attr_reader :node, :merge_type

      # @param node [Prism::Node] The AST node to wrap
      # @param merge_type [Symbol] The merge type (defaults to :nocov)
      def initialize(node, merge_type = :nocov)
        @node = node
        @merge_type = merge_type
      end

      # BlockDirective protocol
      def kind = :nocov
      def children = []
      def merge_policy = nil

      def start_line
        @node.location&.start_line
      end

      def end_line
        @node.location&.end_line
      end

      # Returns the wrapped node (for structural signature generation)
      # @return [Prism::Node]
      def unwrap = @node

      # Delegate location to the wrapped node
      def location = @node.location

      # Content of the wrapped node
      def slice = @node.slice

      # @return [Boolean]
      def nocov_wrapper? = true
      def nocov_node? = false
      def block_directive? = true

      def inspect
        "#<Prism::Merge::NoCovWrapper merge_type=#{@merge_type.inspect} node=#{@node.inspect}>"
      end
    end
  end
end
