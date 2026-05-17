# frozen_string_literal: true

module Ast
  module Merge
    # Chains multiple match refiners sequentially.
    #
    # Each refiner in the pipeline processes the unmatched nodes left over from
    # the previous pass. This allows combining refiners that target different
    # node types or use different scoring strategies (e.g., Levenshtein for
    # paragraphs + Jaccard for comments).
    #
    # Implements the same `#call(template_nodes, dest_nodes, context)` interface
    # as `MatchRefinerBase`, so it can be passed anywhere a single refiner is accepted.
    #
    # @example Combining content and token refiners
    #   composite = CompositeMatchRefiner.new(
    #     ContentMatchRefiner.new(threshold: 0.7, node_types: [:paragraph]),
    #     TokenMatchRefiner.new(threshold: 0.35, node_types: [:comment]),
    #   )
    #   merger = SmartMerger.new(template, dest, match_refiner: composite)
    #
    # @example Adding refiners after construction
    #   composite = CompositeMatchRefiner.new
    #   composite << ContentMatchRefiner.new(threshold: 0.6)
    #   composite << TokenMatchRefiner.new(threshold: 0.35)
    #
    # @see MatchRefinerBase Base class for individual refiners
    class CompositeMatchRefiner
      # @return [Array<#call>] Ordered list of refiners in the pipeline
      attr_reader :refiners

      # Initialize with zero or more refiners.
      #
      # @param refiners [Array<#call>] Refiners to chain, in execution order
      def initialize(*refiners)
        @refiners = refiners.flatten.compact
      end

      # Append a refiner to the pipeline.
      #
      # @param refiner [#call] A match refiner
      # @return [self]
      def <<(refiner)
        @refiners << refiner
        self
      end

      # Run all refiners sequentially.
      #
      # Each refiner receives the unmatched nodes remaining after previous
      # refiners have consumed their matches. All matches are accumulated
      # and returned as a single flat array.
      #
      # @param template_nodes [Array] Unmatched template nodes
      # @param dest_nodes [Array] Unmatched destination nodes
      # @param context [Hash] Additional context passed to each refiner
      # @return [Array<MatchRefinerBase::MatchResult>] All matches from all refiners
      def call(template_nodes, dest_nodes, context = {})
        all_matches = []
        remaining_template = template_nodes.dup
        remaining_dest = dest_nodes.dup

        refiners.each do |refiner|
          next if remaining_template.empty? || remaining_dest.empty?

          matches = Array(refiner.call(remaining_template, remaining_dest, context))
          next if matches.empty?

          matched_template = matches.map(&:template_node)
          matched_dest = matches.map(&:dest_node)

          remaining_template -= matched_template
          remaining_dest -= matched_dest
          all_matches.concat(matches)
        end

        all_matches
      end

      # Whether this composite has any refiners.
      #
      # @return [Boolean]
      def empty?
        refiners.empty?
      end

      # Number of refiners in the pipeline.
      #
      # @return [Integer]
      def size
        refiners.size
      end
    end
  end
end
