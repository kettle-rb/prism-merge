# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # One stack frame in a nested merge session.
      class Frame
        attr_reader :parent_operation_id,
          :operation_id,
          :depth,
          :surface_path,
          :language_chain

        def initialize(parent_operation_id: nil, operation_id:, depth:, surface_path:, language_chain: [])
          @parent_operation_id = parent_operation_id
          @operation_id = operation_id
          @depth = Integer(depth)
          @surface_path = surface_path.to_s
          @language_chain = Array(language_chain).map { |language| language.to_s.strip.downcase.tr("-", "_").to_sym }.freeze
        end

        def root?
          parent_operation_id.nil?
        end

        def to_h
          {
            parent_operation_id: parent_operation_id,
            operation_id: operation_id,
            depth: depth,
            surface_path: surface_path,
            language_chain: language_chain,
            root: root?,
          }
        end
      end
    end
  end
end
