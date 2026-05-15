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

    class SelectionProfile
      KNOWN_OWNER_SELECTORS = {
        "line_bound_statements" => ["line_oriented", "Selects owners from line-bound statements"],
        "heading_sections" => ["section", "Selects heading-owned section branches"]
      }.freeze
      KNOWN_SELECTOR_KINDS = {
        "owner_filter" => ["owner_filter", "Selects structural owners by predicate"],
        "comment_region_owner" => ["comment_anchor", "Selects owners anchored by comment regions"],
        "heading_section" => ["section_branch", "Selects heading-owned section branches"]
      }.freeze
      KNOWN_SELECTION_INTENTS = {
        "predicate_filter" => ["predicate", "Selection is driven by a predicate"],
        "comment_region_filter" => ["comment", "Selection is driven by a comment region"],
        "section_heading" => ["section", "Selection is driven by a section heading"]
      }.freeze
      KNOWN_COMMENT_REGIONS = {
        "leading" => ["leading", "Leading comment region"],
        "trailing" => ["trailing", "Trailing comment region"],
        "inline" => ["inline", "Inline comment region"]
      }.freeze

      attr_reader :owner_scope,
        :owner_selector,
        :selector_kind,
        :selection_intent,
        :comment_region,
        :include_trailing_gap

      def initialize(
        owner_scope: "shared_default",
        owner_selector: "line_bound_statements",
        selector_kind: "owner_filter",
        selection_intent: "predicate_filter",
        comment_region: nil,
        include_trailing_gap: false
      )
        @owner_scope = owner_scope.to_s
        @owner_selector = owner_selector.to_s
        @selector_kind = selector_kind.to_s
        @selection_intent = selection_intent.to_s
        @comment_region = comment_region&.to_s
        @include_trailing_gap = include_trailing_gap
      end

      def report
        owner_selector_family = KNOWN_OWNER_SELECTORS.fetch(owner_selector, ["unknown"]).first
        selector_kind_family = KNOWN_SELECTOR_KINDS.fetch(selector_kind, ["unknown"]).first
        selection_intent_family = KNOWN_SELECTION_INTENTS.fetch(selection_intent, ["unknown"]).first
        comment_region_family = comment_region.nil? ? "none" : KNOWN_COMMENT_REGIONS.fetch(comment_region, ["unknown"]).first
        known_comment_region = !comment_region.nil? && KNOWN_COMMENT_REGIONS.key?(comment_region)
        {
          owner_scope: owner_scope,
          owner_selector: owner_selector,
          owner_selector_family: owner_selector_family,
          known_owner_selector: KNOWN_OWNER_SELECTORS.key?(owner_selector),
          selector_kind: selector_kind,
          selector_kind_family: selector_kind_family,
          known_selector_kind: KNOWN_SELECTOR_KINDS.key?(selector_kind),
          selection_intent: selection_intent,
          selection_intent_family: selection_intent_family,
          known_selection_intent: KNOWN_SELECTION_INTENTS.key?(selection_intent),
          comment_region: comment_region,
          comment_region_family: comment_region_family,
          known_comment_region: known_comment_region,
          comment_anchored: selector_kind_family == "comment_anchor" || selection_intent_family == "comment" || known_comment_region,
          include_trailing_gap: include_trailing_gap
        }
      end
    end

    class DestinationProfile
      KNOWN_RESOLUTION_KINDS = {
        "append_fallback" => ["append", "Insertion fell back to appending at the end of the document"],
        "anchor_after_statement" => ["anchored", "Insertion resolved a statement anchor and spliced after it"]
      }.freeze
      KNOWN_RESOLUTION_SOURCES = {
        "none" => ["implicit", "No destination object was provided"],
        "callable" => ["callable", "Destination was resolved from a callable"],
        "selector" => ["selector", "Destination was resolved from an owner selector anchor"]
      }.freeze
      KNOWN_ANCHOR_BOUNDARIES = {
        "none" => ["none", "No anchor boundary was used"],
        "statement_end_plus_following_gap" => ["gap_preserving_statement", "Insertion anchored after a statement and preserved its following blank-line gap"]
      }.freeze

      attr_reader :resolution_kind, :resolution_source, :anchor_boundary, :used_if_missing

      def initialize(
        resolution_kind: "append_fallback",
        resolution_source: "none",
        anchor_boundary: "none",
        used_if_missing: false
      )
        @resolution_kind = resolution_kind.to_s
        @resolution_source = resolution_source.to_s
        @anchor_boundary = anchor_boundary.to_s
        @used_if_missing = used_if_missing
      end

      def report
        resolution_family = KNOWN_RESOLUTION_KINDS.fetch(resolution_kind, ["unknown"]).first
        {
          resolution_kind: resolution_kind,
          resolution_family: resolution_family,
          known_resolution_kind: KNOWN_RESOLUTION_KINDS.key?(resolution_kind),
          resolution_source: resolution_source,
          resolution_source_family: KNOWN_RESOLUTION_SOURCES.fetch(resolution_source, ["unknown"]).first,
          known_resolution_source: KNOWN_RESOLUTION_SOURCES.key?(resolution_source),
          anchor_boundary: anchor_boundary,
          anchor_boundary_family: KNOWN_ANCHOR_BOUNDARIES.fetch(anchor_boundary, ["unknown"]).first,
          known_anchor_boundary: KNOWN_ANCHOR_BOUNDARIES.key?(anchor_boundary),
          used_if_missing: used_if_missing,
          append_fallback: resolution_kind == "append_fallback",
          anchored: resolution_family == "anchored"
        }
      end
    end

    class OperationProfile
      KNOWN_OPERATION_KINDS = {
        "replace" => ["rewrite", "Replace selected content with explicit replacement text"],
        "delete" => ["removal", "Delete selected content without inserting replacement text"],
        "insert" => ["insertion", "Insert explicit text at a destination anchor or append fallback"],
        "move" => ["relocation", "Relocate selected content or explicit replacement text to a destination anchor"]
      }.freeze
      KNOWN_REQUIREMENTS = %w[none optional required].freeze
      KNOWN_REPLACEMENT_SOURCES = %w[none explicit_text captured_text_or_explicit].freeze

      attr_reader :operation_kind,
        :source_requirement,
        :destination_requirement,
        :replacement_source,
        :captures_source_text,
        :supports_if_missing

      def initialize(
        operation_kind: "replace",
        source_requirement: "required",
        destination_requirement: "none",
        replacement_source: "explicit_text",
        captures_source_text: false,
        supports_if_missing: false
      )
        @operation_kind = operation_kind.to_s
        @source_requirement = source_requirement.to_s
        @destination_requirement = destination_requirement.to_s
        @replacement_source = replacement_source.to_s
        @captures_source_text = captures_source_text
        @supports_if_missing = supports_if_missing
      end

      def report
        operation_family = KNOWN_OPERATION_KINDS.fetch(operation_kind, ["unknown"]).first
        {
          operation_kind: operation_kind,
          operation_family: operation_family,
          known_operation_kind: KNOWN_OPERATION_KINDS.key?(operation_kind),
          source_requirement: source_requirement,
          known_source_requirement: KNOWN_REQUIREMENTS.include?(source_requirement),
          destination_requirement: destination_requirement,
          known_destination_requirement: KNOWN_REQUIREMENTS.include?(destination_requirement),
          replacement_source: replacement_source,
          known_replacement_source: KNOWN_REPLACEMENT_SOURCES.include?(replacement_source),
          captures_source_text: captures_source_text,
          supports_if_missing: supports_if_missing,
          selects_source: source_requirement != "none",
          requires_source: source_requirement == "required",
          supports_destination: destination_requirement != "none",
          requires_destination: destination_requirement == "required",
          explicit_replacement: replacement_source == "explicit_text",
          may_reuse_captured_text: replacement_source == "captured_text_or_explicit"
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
            "match profile helpers",
            "selection profile helpers",
            "destination profile helpers",
            "operation profile helpers"
          ],
          future_exports: [
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

      def selection_profile(
        owner_scope: "shared_default",
        owner_selector: "line_bound_statements",
        selector_kind: "owner_filter",
        selection_intent: "predicate_filter",
        comment_region: nil,
        include_trailing_gap: false
      )
        SelectionProfile.new(
          owner_scope: owner_scope,
          owner_selector: owner_selector,
          selector_kind: selector_kind,
          selection_intent: selection_intent,
          comment_region: comment_region,
          include_trailing_gap: include_trailing_gap
        )
      end

      def destination_profile(
        resolution_kind: "append_fallback",
        resolution_source: "none",
        anchor_boundary: "none",
        used_if_missing: false
      )
        DestinationProfile.new(
          resolution_kind: resolution_kind,
          resolution_source: resolution_source,
          anchor_boundary: anchor_boundary,
          used_if_missing: used_if_missing
        )
      end

      def operation_profile(
        operation_kind: "replace",
        source_requirement: "required",
        destination_requirement: "none",
        replacement_source: "explicit_text",
        captures_source_text: false,
        supports_if_missing: false
      )
        OperationProfile.new(
          operation_kind: operation_kind,
          source_requirement: source_requirement,
          destination_requirement: destination_requirement,
          replacement_source: replacement_source,
          captures_source_text: captures_source_text,
          supports_if_missing: supports_if_missing
        )
      end
    end
  end
end
