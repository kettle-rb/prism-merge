# frozen_string_literal: true

module Ast
  module Merge
    module NodeTyping
      # Thread-safe backend registration and type normalization for AST merge libraries.
      #
      # Normalizer provides a shared, thread-safe mechanism for registering backend-specific
      # node type mappings and normalizing them to canonical types. This enables portable
      # merge rules across different parsers/backends for the same file format.
      #
      # ## Thread Safety
      #
      # All registration and lookup operations are protected by a mutex to ensure
      # thread-safe access to the backend mappings. This follows the same pattern
      # used in TreeHaver::LanguageRegistry and TreeHaver::PathValidator.
      #
      # ## Usage Pattern
      #
      # File-format-specific merge libraries (e.g., toml-merge, markdown-merge) should:
      # 1. Create their own NodeTypeNormalizer module
      # 2. Include or extend Ast::Merge::NodeTyping::Normalizer
      # 3. Define their canonical types and default backend mappings
      # 4. Call `configure_normalizer` with their initial mappings
      #
      # @example Creating a format-specific normalizer
      #   module Toml
      #     module Merge
      #       module NodeTypeNormalizer
      #         extend Ast::Merge::NodeTyping::Normalizer
      #
      #         configure_normalizer(
      #           tree_sitter_toml: {
      #             table_array_element: :array_of_tables,
      #             pair: :pair,
      #             # ...
      #           }.freeze,
      #           citrus_toml: {
      #             table_array_element: :array_of_tables,
      #             pair: :pair,
      #             # ...
      #           }.freeze
      #         )
      #
      #         # Optional: Add format-specific helper methods
      #         def self.table_type?(type)
      #           %i[table array_of_tables].include?(type.to_sym)
      #         end
      #       end
      #     end
      #   end
      #
      # @see TreeHaver::LanguageRegistry
      # @see TreeHaver::PathValidator
      module Normalizer
        # Called when this module is extended into another module.
        # Sets up the mutex and backend mappings storage.
        #
        # @param base [Module] The module extending this one
        class << self
          # Initialize storage on a format-specific normalizer module.
          #
          # @param base [Module] module extending this shared normalizer
          # @return [void]
          def extended(base)
            base.instance_variable_set(:@normalizer_mutex, Mutex.new)
            base.instance_variable_set(:@backend_mappings, {})
          end
        end

        # Configure the normalizer with initial backend mappings.
        #
        # This should be called once when defining the format-specific normalizer,
        # providing the default backend mappings. Additional backends can be
        # registered later via `register_backend`.
        #
        # @param mappings [Hash{Symbol => Hash{Symbol => Symbol}}] Initial backend mappings
        #   Keys are backend identifiers, values are hashes mapping backend types to canonical types
        # @return [void]
        #
        # @example
        #   configure_normalizer(
        #     tree_sitter_toml: { table_array_element: :array_of_tables }.freeze,
        #     citrus_toml: { table_array_element: :array_of_tables }.freeze
        #   )
        def configure_normalizer(**mappings)
          @normalizer_mutex.synchronize do
            mappings.each do |backend, type_mappings|
              @backend_mappings[backend.to_sym] = type_mappings.frozen? ? type_mappings : type_mappings.freeze
            end
          end
          nil
        end

        # Register type mappings for a new backend.
        #
        # This allows extending the normalizer to support additional parsers
        # beyond those configured initially. Thread-safe for runtime registration.
        #
        # @param backend [Symbol] Backend identifier (e.g., :my_parser)
        # @param mappings [Hash{Symbol => Symbol}] Backend type → canonical type mappings
        # @return [void]
        #
        # @example
        #   NodeTypeNormalizer.register_backend(:my_parser, {
        #     my_table: :table,
        #     my_pair: :pair,
        #   })
        def register_backend(backend, mappings)
          @normalizer_mutex.synchronize do
            @backend_mappings[backend.to_sym] = mappings.frozen? ? mappings : mappings.freeze
          end
          nil
        end

        # Get the canonical type for a backend-specific type.
        #
        # If no mapping exists, returns the original type unchanged (passthrough).
        # This allows backend-specific types to pass through for backend-specific
        # merge rules.
        #
        # @param backend_type [Symbol, String, nil] The backend's node type
        # @param backend [Symbol] The backend identifier
        # @return [Symbol, nil] Canonical type (or original if no mapping), nil if input was nil
        #
        # @example
        #   NodeTypeNormalizer.canonical_type(:table_array_element, :tree_sitter_toml)
        #   # => :array_of_tables
        #
        #   NodeTypeNormalizer.canonical_type(:unknown_type, :tree_sitter_toml)
        #   # => :unknown_type (passthrough)
        def canonical_type(backend_type, backend = nil)
          return backend_type if backend_type.nil?

          type_sym = backend_type.to_sym
          @normalizer_mutex.synchronize do
            @backend_mappings.dig(backend, type_sym) || type_sym
          end
        end

        # Wrap a node with its canonical type as merge_type.
        #
        # Uses Ast::Merge::NodeTyping.with_merge_type to create a wrapper
        # that delegates all methods to the underlying node while adding
        # a canonical merge_type attribute.
        #
        # @param node [Object] The backend node to wrap (must respond to #type)
        # @param backend [Symbol] The backend identifier
        # @return [Ast::Merge::NodeTyping::Wrapper] Wrapped node with canonical merge_type
        #
        # @example
        #   wrapped = NodeTypeNormalizer.wrap(node, :tree_sitter_toml)
        #   wrapped.type        # => :table_array_element (original)
        #   wrapped.merge_type  # => :array_of_tables (canonical)
        #   wrapped.unwrap      # => node (original node)
        def wrap(node, backend)
          canonical = canonical_type(node.type, backend)
          Ast::Merge::NodeTyping.with_merge_type(node, canonical)
        end

        # Get all registered backends.
        #
        # @return [Array<Symbol>] Backend identifiers
        def registered_backends
          @normalizer_mutex.synchronize do
            @backend_mappings.keys
          end
        end

        # Check if a backend is registered.
        #
        # @param backend [Symbol] Backend identifier
        # @return [Boolean]
        def backend_registered?(backend)
          @normalizer_mutex.synchronize do
            @backend_mappings.key?(backend.to_sym)
          end
        end

        # Get the mappings for a specific backend.
        #
        # @param backend [Symbol] Backend identifier
        # @return [Hash{Symbol => Symbol}, nil] The mappings or nil if not registered
        def mappings_for(backend)
          @normalizer_mutex.synchronize do
            @backend_mappings[backend.to_sym]
          end
        end

        # Get all canonical types across all backends.
        #
        # @return [Array<Symbol>] Unique canonical type symbols
        def canonical_types
          @normalizer_mutex.synchronize do
            @backend_mappings.values.flat_map(&:values).uniq
          end
        end
      end
    end
  end
end
