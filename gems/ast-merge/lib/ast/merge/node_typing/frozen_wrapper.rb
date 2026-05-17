# frozen_string_literal: true

module Ast
  module Merge
    module NodeTyping
      # Wrapper for frozen AST nodes that includes Freezable behavior.
      #
      # FrozenWrapper extends Wrapper to add freeze node semantics, making the
      # wrapped node satisfy both the NodeTyping API and the Freezable API.
      # This enables composition where frozen nodes are:
      # - Wrapped AST nodes (can unwrap to get original)
      # - Typed nodes (have merge_type)
      # - Freeze nodes (satisfy is_a?(Freezable) and freeze_node?)
      #
      # ## Key Distinction from FreezeNodeBase
      #
      # FrozenWrapper and FreezeNodeBase both include Freezable, but they represent
      # fundamentally different concepts:
      #
      # ### FrozenWrapper (this class)
      # - Wraps an AST node that has a freeze marker in its leading comments
      # - The node is still a structural AST node (e.g., a `gem` call in a gemspec)
      # - During matching, we want to match by the underlying node's IDENTITY
      #   (e.g., the gem name), NOT by the full content
      # - Signature generation should unwrap and use the underlying node's structure
      # - Example: `# token:freeze\ngem "example_gem", "~> 1.0"` wraps a CallNode
      #
      # ### FreezeNodeBase
      # - Represents an explicit freeze block with `# token:freeze ... # token:unfreeze`
      # - The entire block is opaque content that should be preserved verbatim
      # - During matching, we match by the full CONTENT of the block
      # - Signature generation uses freeze_signature (content-based)
      # - Example: A multi-line comment block with custom formatting
      #
      # ## Signature Generation Behavior
      #
      # When FileAnalyzable#generate_signature encounters a FrozenWrapper:
      # 1. It unwraps to get the underlying AST node
      # 2. Passes the unwrapped node to the signature_generator
      # 3. This allows the signature generator to recognize the node type
      #    (e.g., Prism::CallNode) and generate appropriate signatures
      #
      # This is critical because signature generators check for specific AST types.
      # If we passed the wrapper, the generator wouldn't recognize it as a CallNode
      # and would fall back to a generic signature, breaking matching.
      #
      # @example Creating a frozen wrapper
      #   frozen = NodeTyping::FrozenWrapper.new(prism_node, :frozen)
      #   frozen.freeze_node?  # => true
      #   frozen.is_a?(Ast::Merge::Freezable)  # => true
      #   frozen.unwrap  # => prism_node
      #
      # @see Wrapper
      # @see Ast::Merge::Freezable
      # @see FreezeNodeBase
      # @see FileAnalyzable#generate_signature
      class FrozenWrapper < Wrapper
        include Ast::Merge::Freezable

        # Create a frozen wrapper for an AST node.
        #
        # @param node [Object] The AST node to wrap
        # @param merge_type [Symbol] The merge type (defaults to :frozen)
        def initialize(node, merge_type = :frozen)
          super(node, merge_type)
        end

        # Returns true to indicate this is a frozen node.
        # Overrides both Wrapper#typed_node? context and provides freeze_node? from Freezable.
        #
        # @return [Boolean] true
        def frozen_node?
          true
        end

        # Returns the content of this frozen node.
        # Delegates to the wrapped node's slice method.
        #
        # @return [String] The node content
        def slice
          @node.slice
        end

        # Returns the signature for this frozen node.
        # Uses the freeze_signature from Freezable module.
        #
        # @return [Array] Signature in the form [:FreezeNode, content]
        def signature
          freeze_signature
        end

        # Forward inspect to show frozen status.
        def inspect
          "#<NodeTyping::FrozenWrapper merge_type=#{@merge_type.inspect} node=#{@node.inspect}>"
        end
      end
    end
  end
end
