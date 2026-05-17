# frozen_string_literal: true

module Ast
  module Merge
    module Layout
      # Passive per-owner container for adjacent blank-line gaps.
      #
      # An attachment can reference a leading gap, a trailing gap, or both. The
      # same shared gap object may appear in attachments for adjacent owners.
      class Attachment
        attr_reader :owner, :leading_gap, :trailing_gap, :metadata

        def initialize(owner: nil, leading_gap: nil, trailing_gap: nil, metadata: {}, **options)
          @owner = owner
          @leading_gap = leading_gap
          @trailing_gap = trailing_gap
          @metadata = metadata.merge(options).freeze
        end

        # Return all distinct gaps referenced by this attachment.
        #
        # @return [Array<Gap>]
        def gaps
          [leading_gap, trailing_gap].compact.uniq
        end

        def empty?
          gaps.empty?
        end

        def leading_controls_output?(**options)
          leading_gap&.controls_output_for?(owner, **options) || false
        end

        def trailing_controls_output?(**options)
          trailing_gap&.controls_output_for?(owner, **options) || false
        end

        # Return a concise debug representation of the attachment.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} owner=#{owner&.class&.name} gaps=#{gaps.size}>"
        end
      end
    end
  end
end
