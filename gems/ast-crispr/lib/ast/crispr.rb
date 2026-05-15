# frozen_string_literal: true

require "ast/merge"
require_relative "crispr/version"

module Ast
  module Crispr
    PACKAGE_NAME = "ast-crispr"

    class Error < StandardError
      attr_reader :code, :details

      def initialize(message, code:, details: {})
        @code = code
        @details = details
        super(message)
      end
    end

    class Limit
      Constraint = Struct.new(:description, :predicate, keyword_init: true)

      class << self
        def coerce(spec = nil)
          spec.is_a?(self) ? spec : new(spec)
        end
      end

      attr_reader :constraints

      def initialize(spec = nil)
        @constraints = normalize(spec.nil? ? {exactly: 1} : spec)
      end

      def allows?(count)
        constraints.all? { |constraint| constraint.predicate.call(Integer(count)) }
      end

      def describe
        constraints.map(&:description).join(" and ")
      end

      private

      def normalize(spec)
        case spec
        when Limit
          spec.constraints
        when Hash
          normalize_hash(spec)
        when Array
          spec.flat_map { |entry| normalize(entry) }
        when String
          [constraint_for_operator(spec)]
        else
          raise Error.new(
            "Unsupported ast-crispr limit specification",
            code: "ast_crispr_limit_unsupported",
            details: {spec: spec.inspect}
          )
        end
      end

      def normalize_hash(spec)
        constraints = []
        constraints << constraint("== #{Integer(spec.fetch(:exactly))}") { |count| count == Integer(spec.fetch(:exactly)) } if spec.key?(:exactly)
        constraints << constraint("<= #{Integer(spec.fetch(:at_most))}") { |count| count <= Integer(spec.fetch(:at_most)) } if spec.key?(:at_most)
        constraints << constraint(">= #{Integer(spec.fetch(:at_least))}") { |count| count >= Integer(spec.fetch(:at_least)) } if spec.key?(:at_least)
        constraints << constraint("<= 1") { |count| count <= 1 } if spec[:none_or_one]
        raise Error.new("ast-crispr limit must define at least one constraint", code: "ast_crispr_limit_empty", details: {spec: spec.inspect}) if constraints.empty?

        constraints
      end

      def constraint_for_operator(spec)
        match = /\A(==|!=|<=|>=|<|>)\s*(\d+)\z/.match(spec.strip)
        raise Error.new("Invalid ast-crispr limit expression", code: "ast_crispr_limit_invalid_expression", details: {spec: spec.inspect}) unless match

        operator = match[1]
        value = match[2].to_i
        constraint("#{operator} #{value}") do |count|
          case operator
          when "==" then count == value
          when "!=" then count != value
          when "<=" then count <= value
          when ">=" then count >= value
          when "<" then count < value
          when ">" then count > value
          else false
          end
        end
      end

      def constraint(description, &predicate)
        Constraint.new(description: description, predicate: predicate)
      end
    end

    class MatchProfile
      KNOWN_START_BOUNDARIES = {
        "owner_start" => ["structural_owner", "Span starts at the structural owner's boundary"],
        "comment_region_start" => ["comment_anchor", "Span starts at an owning comment-region boundary"]
      }.freeze
      KNOWN_END_BOUNDARIES = {
        "owner_end" => ["structural_owner", "Span ends at the structural owner's boundary"],
        "owner_end_plus_trailing_gap" => ["gap_extension", "Span extends past the owner boundary to include trailing blank-line gap"]
      }.freeze
      KNOWN_PAYLOAD_KINDS = {
        "structural_owner_body" => ["owner_body", "Span represents a structural owner's body"],
        "comment_owned_body" => ["comment_owned", "Span represents a structural owner body selected through an owning comment marker"],
        "section_branch" => ["section_branch", "Span represents a heading-owned section branch payload"]
      }.freeze

      attr_reader :start_boundary, :end_boundary, :payload_kind

      def initialize(start_boundary: "owner_start", end_boundary: "owner_end", payload_kind: "structural_owner_body")
        @start_boundary = start_boundary.to_s
        @end_boundary = end_boundary.to_s
        @payload_kind = payload_kind.to_s
      end

      def report
        start_family = KNOWN_START_BOUNDARIES.fetch(start_boundary, ["unknown"]).first
        end_family = KNOWN_END_BOUNDARIES.fetch(end_boundary, ["unknown"]).first
        payload_family = KNOWN_PAYLOAD_KINDS.fetch(payload_kind, ["unknown"]).first
        {
          start_boundary: start_boundary,
          start_boundary_family: start_family,
          known_start_boundary: KNOWN_START_BOUNDARIES.key?(start_boundary),
          end_boundary: end_boundary,
          end_boundary_family: end_family,
          known_end_boundary: KNOWN_END_BOUNDARIES.key?(end_boundary),
          payload_kind: payload_kind,
          payload_family: payload_family,
          known_payload_kind: KNOWN_PAYLOAD_KINDS.key?(payload_kind),
          comment_anchored: start_family == "comment_anchor" || payload_family == "comment_owned",
          trailing_gap_extended: end_family == "gap_extension"
        }
      end
    end

    class << self
      def ast_merge_contract_anchor
        "Ast::Merge.structured_edit"
      end

      def boundary_report
        {
          package: PACKAGE_NAME,
          layer: "structural_edit_tool",
          status: "active_thin_package",
          base_contract_package: "ast-merge",
          relationship: {
            ast_merge: [
              "owns portable structured-edit envelope contracts",
              "owns transport, report, replay, review, and provider handoff vocabulary",
              "remains the substrate for provider-neutral fixtures"
            ],
            ast_crispr: [
              "owns ergonomic structural-edit selectors, profiles, and operation helpers",
              "wraps ast-merge contracts instead of forking them",
              "may grow compatibility helpers for old ast-crispr concepts after fixture-backed review"
            ],
            provider_packages: [
              "own parser-specific execution and metadata projection",
              "may expose provider adapters consumed by ast-crispr",
              "keep raw parser details behind normalized tree metadata or semantic sidecars"
            ],
            ast_template: [
              "orchestrates template and directory workflows",
              "invokes structural edits through ast-merge or ast-crispr registries/envelopes",
              "does not own parser-specific selectors"
            ]
          },
          implementations: [
            {
              language: "go",
              package_name: "astcrispr",
              import: "github.com/structuredmerge/structuredmerge-go/astcrispr"
            },
            {
              language: "ruby",
              package_name: "ast-crispr",
              require: "ast/crispr"
            },
            {
              language: "rust",
              package_name: "ast-crispr",
              crate: "ast_crispr"
            },
            {
              language: "typescript",
              package_name: "@structuredmerge/ast-crispr",
              import: "@structuredmerge/ast-crispr"
            }
          ],
          initial_exports: [
            "package identity",
            "boundary report",
            "ast-merge structured-edit contract anchor",
            "limit helpers",
            "match profile helpers"
          ],
          future_exports: [
            "selection profile helpers",
            "destination profile helpers",
            "operation profile helpers",
            "replace/delete/insert/move helpers",
            "batch operation helpers"
          ],
          metadata: {
            source: "legacy_crispr_reference",
            decision: "Keep ast-merge as the base contract layer and revive ast-crispr as a separate thin package in every implementation."
          }
        }
      end

      def limit(spec = nil)
        Limit.coerce(spec)
      end

      def match_profile(start_boundary: "owner_start", end_boundary: "owner_end", payload_kind: "structural_owner_body")
        MatchProfile.new(start_boundary: start_boundary, end_boundary: end_boundary, payload_kind: payload_kind)
      end
    end
  end
end
