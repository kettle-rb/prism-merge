# frozen_string_literal: true

module Ast
  module Merge
    module NodeTyping
      # Node wrapper that adds a merge_type attribute to an existing node.
      # This uses a simple delegation pattern to preserve all original node
      # behavior while adding the merge_type.
      class Wrapper
        # @return [Object] The original node being wrapped
        attr_reader :node

        # @return [Symbol] The custom merge type for this node
        attr_reader :merge_type

        # Create a new node type wrapper.
        #
        # @param node [Object] The original node to wrap
        # @param merge_type [Symbol] The custom merge type
        def initialize(node, merge_type)
          @node = node
          @merge_type = merge_type
        end

        # Delegate all unknown methods to the wrapped node.
        # This allows the wrapper to be used transparently in place of the node.
        def method_missing(method, *args, &block)
          if @node.respond_to?(method)
            @node.send(method, *args, &block)
          else
            super
          end
        end

        # Check if the wrapped node responds to a method.
        def respond_to_missing?(method, include_private = false)
          @node.respond_to?(method, include_private) || super
        end

        # Returns true to indicate this is a node type wrapper.
        def typed_node?
          true
        end

        # Unwrap to get the original node.
        # @return [Object] The original unwrapped node
        def unwrap
          @node
        end

        # Forward equality check to the wrapped node.
        def ==(other)
          if other.is_a?(Wrapper)
            @node == other.node && @merge_type == other.merge_type
          else
            @node == other
          end
        end

        # Forward hash to the wrapped node.
        def hash
          [@node, @merge_type].hash
        end

        # Forward eql? to the wrapped node.
        def eql?(other)
          self == other
        end

        # Forward inspect to show both the type and node.
        def inspect
          "#<NodeTyping::Wrapper merge_type=#{@merge_type.inspect} node=#{@node.inspect}>"
        end
      end
    end
  end
end
