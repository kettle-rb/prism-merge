# frozen_string_literal: true

module Prism
  module Merge
    # Wraps tree_haver nodes with a unified interface for merging.
    # Provides #canonical_type, semantic predicates, and method_missing
    # delegation to the underlying node.
    class NodeWrapper
      attr_reader :node, :backend

      class << self
        # Wrap a node, returning nil for nil input.
        #
        # @param node [Object, nil] Node to wrap
        # @param backend [Symbol] The backend used for parsing (defaults to :prism)
        # @return [NodeWrapper, nil] Wrapped node or nil if node is nil
        def wrap(node, backend: :prism)
          return nil if node.nil?

          new(node, backend: backend)
        end
      end

      # @param node [Object] TreeHaver::Backends::Prism::Node or similar
      # @param backend [Symbol] The backend identifier
      def initialize(node, backend: :prism)
        @node = node
        @backend = backend
      end

      # Get the raw type from the underlying node
      # @return [String, Symbol]
      def type
        @node.type
      end

      # Get the canonical (normalized) type for this node
      # @return [Symbol]
      def canonical_type
        NodeTypeNormalizer.canonical_type(@node.type, @backend)
      end

      # Semantic predicates
      def def? = canonical_type == :def
      def class? = canonical_type == :class
      def module? = canonical_type == :module
      def singleton_class? = canonical_type == :singleton_class
      def call? = canonical_type == :call
      def call_with_block? = call? && block
      def const? = canonical_type == :const
      def local_var? = canonical_type == :local_var
      def ivar? = canonical_type == :ivar
      def cvar? = canonical_type == :cvar
      def gvar? = canonical_type == :gvar
      def multi_write? = canonical_type == :multi_write
      def if? = canonical_type == :if
      def unless? = canonical_type == :unless
      def case? = canonical_type == :case
      def case_match? = canonical_type == :case_match
      def while? = canonical_type == :while
      def until? = canonical_type == :until
      def for? = canonical_type == :for
      def begin? = canonical_type == :begin
      def rescue? = canonical_type == :rescue
      def lambda? = canonical_type == :lambda
      def pre_execution? = canonical_type == :pre_execution
      def post_execution? = canonical_type == :post_execution

      def method_missing(name, *args, **kwargs, &block_arg)
        if @node.respond_to?(name)
          @node.public_send(name, *args, **kwargs, &block_arg)
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        @node.respond_to?(name, include_private) || super
      end
    end
  end
end
