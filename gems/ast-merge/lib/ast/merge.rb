# frozen_string_literal: true

require "json"
require "token/resolver"
require_relative "merge/version"

module Ast
  module Merge
    PACKAGE_NAME = "ast-merge"
    REVIEW_TRANSPORT_VERSION = 1
    STRUCTURED_EDIT_TRANSPORT_VERSION = 1
    TEMPLATE_TOKEN_CONFIG = Token::Resolver::Config.new(separators: ["|", ":"]).freeze
    COMPACT_RULESET_REQUIRED_DIRECTIVES = %w[format owners match read attach].freeze
    COMPACT_RULESET_SINGLETON_DIRECTIVES = %w[
      format owners match read attach comment_style render render_strategy
    ].freeze
    COMPACT_RULESET_REPEATABLE_KEYED_DIRECTIVES = %w[
      backend node_role atomic child_group capability logical_owner repair surface delegate
    ].freeze
    COMPACT_RULESET_READ_VALUES = %w[source_augmented_portable_write native_read_portable_write native_mutation].freeze
    COMPACT_RULESET_ATTACH_VALUES = %w[
      layout_only
      tracker_layout_merge
      augmenter_preferred_tracker_layout
      normalize_tracked_layout_merge
    ].freeze

    MergeIRNodeClass = Struct.new(:class_id, :signature, :node_ids, :roles, keyword_init: true) do
      def to_h
        {
          class_id: class_id,
          signature: signature,
          node_ids: node_ids || {},
          roles: roles || []
        }
      end
    end

    MergeIROrderedNode = Struct.new(:node_id, :parent_id, :child_ids, :previous_sibling_id, :next_sibling_id, keyword_init: true) do
      def to_h
        {
          node_id: node_id,
          parent_id: parent_id,
          child_ids: child_ids || [],
          previous_sibling_id: previous_sibling_id,
          next_sibling_id: next_sibling_id
        }
      end
    end

    MergeIRChange = Struct.new(
      :change_id,
      :side,
      :kind,
      :node_id,
      :class_id,
      :parent_id,
      :previous_sibling_id,
      :next_sibling_id,
      :content_hash,
      keyword_init: true
    ) do
      def to_h
        {
          change_id: change_id,
          side: side,
          kind: kind,
          node_id: node_id,
          class_id: class_id,
          parent_id: parent_id,
          previous_sibling_id: previous_sibling_id,
          next_sibling_id: next_sibling_id,
          content_hash: content_hash
        }
      end
    end

    MergeIR = Struct.new(:version, :tree_id, :source, :node_classes, :ordered_nodes, :changes, :diagnostics, keyword_init: true) do
      def to_h
        {
          version: version,
          tree_id: tree_id,
          source: source,
          node_classes: (node_classes || []).map(&:to_h),
          ordered_nodes: (ordered_nodes || []).map(&:to_h),
          changes: (changes || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    PairwiseNodeMatch = Struct.new(:from_node_id, :to_node_id, :class_id, :strategy, :confidence, :diagnostics, keyword_init: true) do
      def to_h
        {
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          class_id: class_id,
          strategy: strategy,
          confidence: confidence,
          diagnostics: diagnostics || []
        }
      end
    end

    PairwiseMatching = Struct.new(:matching_id, :from_revision, :to_revision, :matches, :unmatched_from, :unmatched_to, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          from_revision: from_revision,
          to_revision: to_revision,
          matches: (matches || []).map(&:to_h),
          unmatched_from: unmatched_from || [],
          unmatched_to: unmatched_to || []
        }
      end
    end

    ClassMappingNodeClass = Struct.new(:class_id, :signature, :node_ids, :matching_ids, :diagnostics, keyword_init: true) do
      def to_h
        {
          class_id: class_id,
          signature: signature,
          node_ids: node_ids || {},
          matching_ids: matching_ids || [],
          diagnostics: diagnostics || []
        }
      end
    end

    ClassMappingDiagnostic = Struct.new(:severity, :category, :class_id, :message, :matching_ids, keyword_init: true) do
      def to_h
        {
          severity: severity,
          category: category,
          class_id: class_id,
          message: message,
          matching_ids: matching_ids || []
        }
      end
    end

    ClassMappingReport = Struct.new(:mapping_id, :source_matching_ids, :node_classes, :diagnostics, keyword_init: true) do
      def to_h
        {
          mapping_id: mapping_id,
          source_matching_ids: source_matching_ids || [],
          node_classes: (node_classes || []).map(&:to_h),
          diagnostics: (diagnostics || []).map(&:to_h)
        }
      end
    end

    PCSConstraint = Struct.new(:constraint_id, :revision, :parent_class_id, :predecessor_class_id, :successor_class_id, :relation, keyword_init: true) do
      def to_h
        {
          constraint_id: constraint_id,
          revision: revision,
          parent_class_id: parent_class_id,
          predecessor_class_id: predecessor_class_id,
          successor_class_id: successor_class_id,
          relation: relation
        }
      end
    end

    PCS = Struct.new(:pcs_id, :tree_id, :base_revision, :constraints, keyword_init: true) do
      def to_h
        {
          pcs_id: pcs_id,
          tree_id: tree_id,
          base_revision: base_revision,
          constraints: (constraints || []).map(&:to_h)
        }
      end
    end

    ChangeSetChange = Struct.new(:change_id, :kind, :class_id, :parent_class_id, :predecessor_class_id, :successor_class_id, :content_hash, keyword_init: true) do
      def to_h
        {
          change_id: change_id,
          kind: kind,
          class_id: class_id,
          parent_class_id: parent_class_id,
          predecessor_class_id: predecessor_class_id,
          successor_class_id: successor_class_id,
          content_hash: content_hash
        }
      end
    end

    ChangeSet = Struct.new(:change_set_id, :side, :changes, :diagnostics, keyword_init: true) do
      def to_h
        {
          change_set_id: change_set_id,
          side: side,
          changes: (changes || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    RawMergeChange = Struct.new(:change_id, :source_change_set_id, :side, :kind, :class_id, :parent_class_id, :predecessor_class_id, :successor_class_id, :content_hash, keyword_init: true) do
      def to_h
        {
          change_id: change_id,
          source_change_set_id: source_change_set_id,
          side: side,
          kind: kind,
          class_id: class_id,
          parent_class_id: parent_class_id,
          predecessor_class_id: predecessor_class_id,
          successor_class_id: successor_class_id,
          content_hash: content_hash
        }
      end
    end

    RawMerge = Struct.new(:raw_merge_id, :input_change_set_ids, :changes, :diagnostics, keyword_init: true) do
      def to_h
        {
          raw_merge_id: raw_merge_id,
          input_change_set_ids: input_change_set_ids || [],
          changes: (changes || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    MergeInconsistency = Struct.new(:inconsistency_id, :category, :severity, :class_ids, :change_ids, :message, keyword_init: true) do
      def to_h
        {
          inconsistency_id: inconsistency_id,
          category: category,
          severity: severity,
          class_ids: class_ids || [],
          change_ids: change_ids || [],
          message: message
        }
      end
    end

    InconsistencyReport = Struct.new(:report_id, :raw_merge_id, :inconsistencies, :diagnostics, keyword_init: true) do
      def to_h
        {
          report_id: report_id,
          raw_merge_id: raw_merge_id,
          inconsistencies: (inconsistencies || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    MergeIRComparisonCase = Struct.new(:case_id, :family, :scenario, :owner_path_outcome, :merge_ir_outcome, :merge_ir_advantage, :diagnostics, keyword_init: true) do
      def to_h
        {
          case_id: case_id,
          family: family,
          scenario: scenario,
          owner_path_outcome: owner_path_outcome,
          merge_ir_outcome: merge_ir_outcome,
          merge_ir_advantage: merge_ir_advantage,
          diagnostics: diagnostics || []
        }
      end
    end

    MergeIRComparisonSummary = Struct.new(:owner_path_wins, :merge_ir_wins, :neutral, :defer, :recommendation, keyword_init: true) do
      def to_h
        {
          owner_path_wins: owner_path_wins,
          merge_ir_wins: merge_ir_wins,
          neutral: neutral,
          defer: defer,
          recommendation: recommendation
        }
      end
    end

    MergeIRComparisonReport = Struct.new(:comparison_id, :baseline, :prototype, :cases, :summary, keyword_init: true) do
      def to_h
        {
          comparison_id: comparison_id,
          baseline: baseline,
          prototype: prototype,
          cases: (cases || []).map(&:to_h),
          summary: summary.to_h
        }
      end
    end

    StructuralPathMatch = Struct.new(:from_path, :to_path, :from_node_id, :to_node_id, :confidence, keyword_init: true) do
      def to_h
        {
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          confidence: confidence
        }
      end
    end

    StructuralMatchingReport = Struct.new(:matching_id, :strategy, :from_revision, :to_revision, :matches, :unmatched_from, :unmatched_to, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          from_revision: from_revision,
          to_revision: to_revision,
          matches: (matches || []).map(&:to_h),
          unmatched_from: unmatched_from || [],
          unmatched_to: unmatched_to || [],
          diagnostics: diagnostics || []
        }
      end
    end

    SignatureMatchingParent = Struct.new(:kind, :role, :from_path, :to_path, :from_node_id, :to_node_id, :child_order, keyword_init: true) do
      def to_h
        {
          kind: kind,
          role: role,
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          child_order: child_order
        }
      end
    end

    SignatureNodeMatch = Struct.new(:signature, :from_path, :to_path, :from_node_id, :to_node_id, :confidence, :diagnostics, keyword_init: true) do
      def to_h
        {
          signature: signature,
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          confidence: confidence,
          diagnostics: diagnostics || []
        }
      end
    end

    SignatureMatchingReport = Struct.new(:matching_id, :strategy, :parent_policy, :signature_components, :from_revision, :to_revision, :matches, :unmatched_from, :unmatched_to, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          parent_policy: parent_policy,
          signature_components: signature_components || [],
          from_revision: from_revision,
          to_revision: to_revision,
          matches: (matches || []).map(&:to_h),
          unmatched_from: unmatched_from || [],
          unmatched_to: unmatched_to || [],
          diagnostics: diagnostics || []
        }
      end
    end

    SourceTextNormalizedMatch = Struct.new(:normalized_text, :from_path, :to_path, :from_node_id, :to_node_id, :from_source_text, :to_source_text, :confidence, :diagnostics, keyword_init: true) do
      def to_h
        {
          normalized_text: normalized_text,
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          from_source_text: from_source_text,
          to_source_text: to_source_text,
          confidence: confidence,
          diagnostics: diagnostics || []
        }
      end
    end

    SourceTextNormalizedMatchingReport = Struct.new(:matching_id, :strategy, :from_revision, :to_revision, :normalization, :leaf_kinds, :matches, :unmatched_from, :unmatched_to, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          from_revision: from_revision,
          to_revision: to_revision,
          normalization: normalization || [],
          leaf_kinds: leaf_kinds || [],
          matches: (matches || []).map(&:to_h),
          unmatched_from: unmatched_from || [],
          unmatched_to: unmatched_to || [],
          diagnostics: diagnostics || []
        }
      end
    end

    MoveDetectionCapability = Struct.new(:name, :enabled, :default_enabled, :requires_stable_node_identity, keyword_init: true) do
      def to_h
        {
          name: name,
          enabled: enabled,
          default_enabled: default_enabled,
          requires_stable_node_identity: requires_stable_node_identity
        }
      end
    end

    MoveDetectionMatch = Struct.new(:from_path, :to_path, :from_node_id, :to_node_id, :signature, :moved, :from_parent_path, :to_parent_path, :from_index, :to_index, :confidence, :diagnostics, keyword_init: true) do
      def to_h
        {
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          signature: signature,
          moved: moved,
          from_parent_path: from_parent_path,
          to_parent_path: to_parent_path,
          from_index: from_index,
          to_index: to_index,
          confidence: confidence,
          diagnostics: diagnostics || []
        }
      end
    end

    MoveDetectionMatchingReport = Struct.new(:matching_id, :strategy, :from_revision, :to_revision, :capability, :matches, :unmatched_from, :unmatched_to, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          from_revision: from_revision,
          to_revision: to_revision,
          capability: capability.to_h,
          matches: (matches || []).map(&:to_h),
          unmatched_from: unmatched_from || [],
          unmatched_to: unmatched_to || [],
          diagnostics: diagnostics || []
        }
      end
    end

    RenameAwareCapability = Struct.new(:name, :status, :enabled, :requires_explicit_profile, :requires_diagnostics, keyword_init: true) do
      def to_h
        {
          name: name,
          status: status,
          enabled: enabled,
          requires_explicit_profile: requires_explicit_profile,
          requires_diagnostics: requires_diagnostics
        }
      end
    end

    RenameAwareCandidate = Struct.new(:from_path, :to_path, :from_node_id, :to_node_id, :from_signature, :to_signature, :stable_body_hash, :rename_distance, :selected, :diagnostics, keyword_init: true) do
      def to_h
        {
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          from_signature: from_signature,
          to_signature: to_signature,
          stable_body_hash: stable_body_hash,
          rename_distance: rename_distance,
          selected: selected,
          diagnostics: diagnostics || []
        }
      end
    end

    RenameAwareMatchingReport = Struct.new(:matching_id, :strategy, :from_revision, :to_revision, :capability, :candidates, :matches, :unmatched_from, :unmatched_to, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          from_revision: from_revision,
          to_revision: to_revision,
          capability: capability.to_h,
          candidates: (candidates || []).map(&:to_h),
          matches: (matches || []).map(&:to_h),
          unmatched_from: unmatched_from || [],
          unmatched_to: unmatched_to || [],
          diagnostics: diagnostics || []
        }
      end
    end

    MatchingAmbiguity = Struct.new(:signature, :scope_path, :from_candidates, :to_candidates, :selected, :reason, :diagnostics, keyword_init: true) do
      def to_h
        {
          signature: signature,
          scope_path: scope_path,
          from_candidates: from_candidates || [],
          to_candidates: to_candidates || [],
          selected: selected,
          reason: reason,
          diagnostics: diagnostics || []
        }
      end
    end

    AmbiguityMatchingReport = Struct.new(:matching_id, :strategy, :scope_path, :ambiguous, :matches, :ambiguities, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          scope_path: scope_path,
          ambiguous: ambiguous,
          matches: (matches || []).map(&:to_h),
          ambiguities: (ambiguities || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    RejectedTieBreakCandidate = Struct.new(:from_path, :from_node_id, :confidence, :rejected_by, keyword_init: true) do
      def to_h
        {
          from_path: from_path,
          from_node_id: from_node_id,
          confidence: confidence,
          rejected_by: rejected_by
        }
      end
    end

    TieBreakMatch = Struct.new(:signature, :from_path, :to_path, :from_node_id, :to_node_id, :confidence, :selected_by, :rejected_candidates, :diagnostics, keyword_init: true) do
      def to_h
        {
          signature: signature,
          from_path: from_path,
          to_path: to_path,
          from_node_id: from_node_id,
          to_node_id: to_node_id,
          confidence: confidence,
          selected_by: selected_by,
          rejected_candidates: (rejected_candidates || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    TieBreakMatchingReport = Struct.new(:matching_id, :strategy, :scope_path, :tie_break_rules, :matches, :diagnostics, keyword_init: true) do
      def to_h
        {
          matching_id: matching_id,
          strategy: strategy,
          scope_path: scope_path,
          tie_break_rules: tie_break_rules || [],
          matches: (matches || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    MatchingDebugOwnerSet = Struct.new(:owner_id, :scope_path, :node_paths, keyword_init: true)
    MatchingDebugCandidate = Struct.new(:candidate_id, :signature, :from_path, :to_path, :confidence, :reason, keyword_init: true)
    MatchingDebugSelectedMatch = Struct.new(:candidate_id, :selected_by, keyword_init: true)
    MatchingDebugRejectedMatch = Struct.new(:candidate_id, :rejected_by, :reason, keyword_init: true)

    MatchingDebugArtifacts = Struct.new(:artifact_id, :matching_id, :enabled, :owner_sets, :candidates, :selected_matches, :rejected_matches, :diagnostics, keyword_init: true) do
      def to_h
        {
          artifact_id: artifact_id,
          matching_id: matching_id,
          enabled: enabled,
          owner_sets: (owner_sets || []).map(&:to_h),
          candidates: (candidates || []).map(&:to_h),
          selected_matches: (selected_matches || []).map(&:to_h),
          rejected_matches: (rejected_matches || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    FallbackScopeDefinition = Struct.new(:scope, :path, :owner_path, :covers_children, :requires_source_span, :description, keyword_init: true)

    FallbackScopeReport = Struct.new(:report_id, :version, :scopes, :default_order, :diagnostics, keyword_init: true) do
      def to_h
        {
          report_id: report_id,
          version: version,
          scopes: (scopes || []).map(&:to_h),
          default_order: default_order || [],
          diagnostics: diagnostics || []
        }
      end
    end

    MergeConflict = Struct.new(:conflict_id, :category, :path, :fallback_scope, :message, keyword_init: true)

    ConflictCategoryReport = Struct.new(:report_id, :version, :categories, :conflicts, :diagnostics, keyword_init: true) do
      def to_h
        {
          report_id: report_id,
          version: version,
          categories: categories || [],
          conflicts: (conflicts || []).map(&:to_h),
          diagnostics: diagnostics || []
        }
      end
    end

    LineSpan = Struct.new(:start_line, :end_line, keyword_init: true)

    LocalLineFallbackReport = Struct.new(:fallback_id, :strategy, :scope, :path, :owner_path, :base_span, :left_span, :right_span, :result, :conflict_category, :diagnostics, keyword_init: true)

    ConflictMarkerRenderingReport = Struct.new(:render_id, :strategy, :marker_size, :path_label, :left_label, :base_label, :right_label, :include_base, :output, :diagnostics, keyword_init: true)

    ConflictHandlerRegistration = Struct.new(:handler_id, :conflict_category, :fallback_scope, :node_roles, :capability, :enabled, keyword_init: true)

    ConflictHandlerRegistryReport = Struct.new(:registry_id, :version, :handlers, :diagnostics, keyword_init: true)

    HandlerChildNode = Struct.new(:node_id, :signature, :source, keyword_init: true)
    HandlerKeyedMember = Struct.new(:key, :value, keyword_init: true)
    GenericConflictHandlerResult = Struct.new(:resolved, :merged_children, :merged_members, :diagnostics, keyword_init: true)
    GenericConflictHandlerCase = Struct.new(:case_id, :handler_id, :conflict_category, :parent_policy, :base_children, :left_insertions, :right_insertions, :base_members, :left_edits, :right_edits, :expected_result, keyword_init: true)
    GenericConflictHandlerExecution = Struct.new(:execution_id, :version, :cases, :diagnostics, keyword_init: true)

    LanguageProfileHandlerRegistration = Struct.new(:role, :handler_id, :conflict_categories, :enabled, keyword_init: true)
    LanguageProfileHandlerRegistry = Struct.new(:profile_id, :language, :version, :registrations, :diagnostics, keyword_init: true)

    FallbackUsageEntry = Struct.new(:fallback_id, :strategy, :scope, :path, :conflict_category, keyword_init: true)
    FallbackUsageSummary = Struct.new(:fallback_count, :conflict_count, :resolved_count, keyword_init: true)
    FallbackUsageMachineOutput = Struct.new(:fallbacks, :summary, keyword_init: true)
    GitDriverOutput = Struct.new(:stdout, :stderr, :exit_code, keyword_init: true)
    FallbackUsageReport = Struct.new(:report_id, :version, :mode, :quiet_by_default, :machine_output, :git_driver_output, :diagnostics, keyword_init: true)

    RenderByteSpan = Struct.new(:start_byte, :end_byte, keyword_init: true)
    RenderStrategyMetadata = Struct.new(:strategy, :path, :span, :preserves_source_fragment, :requires_reparse, keyword_init: true)
    RenderPlanReport = Struct.new(:plan_id, :version, :language, :strategies, :diagnostics, keyword_init: true)

    module_function

    GENERIC_INDEPENDENT_COMMUTATIVE_INSERTIONS_HANDLER = "generic-independent-commutative-insertions"
    GENERIC_KEYED_MEMBER_EDIT_HANDLER = "generic-keyed-member-edit"

    def execute_generic_conflict_handler(handler_case)
      case handler_case.handler_id
      when GENERIC_INDEPENDENT_COMMUTATIVE_INSERTIONS_HANDLER
        execute_independent_commutative_insertions(handler_case)
      when GENERIC_KEYED_MEMBER_EDIT_HANDLER
        execute_independent_keyed_member_edits(handler_case)
      else
        GenericConflictHandlerResult.new(
          resolved: false,
          diagnostics: ["unsupported generic conflict handler"]
        )
      end
    end

    def execute_independent_commutative_insertions(handler_case)
      unless handler_case.parent_policy == "commutative"
        return GenericConflictHandlerResult.new(
          resolved: false,
          diagnostics: ["independent insertion handler requires a commutative parent"]
        )
      end

      seen = {}
      merged = []
      [handler_case.base_children, handler_case.left_insertions, handler_case.right_insertions].each do |nodes|
        (nodes || []).each do |node|
          key = node.signature.to_s.empty? ? node.node_id : node.signature
          next if seen[key]

          seen[key] = true
          merged << node
        end
      end

      GenericConflictHandlerResult.new(
        resolved: true,
        merged_children: merged,
        diagnostics: ["independent insertions into a commutative parent were unioned deterministically"]
      )
    end

    def execute_independent_keyed_member_edits(handler_case)
      order = []
      values = {}
      set_member = lambda do |member|
        order << member.key unless values.key?(member.key)
        values[member.key] = member.value
      end

      (handler_case.base_members || []).each { |member| set_member.call(member) }
      (handler_case.left_edits || []).each { |member| set_member.call(member) }
      (handler_case.right_edits || []).each do |member|
        if values.key?(member.key) &&
            values[member.key] != member.value &&
            (handler_case.left_edits || []).any? { |left| left.key == member.key }
          return GenericConflictHandlerResult.new(
            resolved: false,
            diagnostics: ["keyed member was edited differently on both sides"]
          )
        end
        set_member.call(member)
      end

      GenericConflictHandlerResult.new(
        resolved: true,
        merged_members: order.map { |key| HandlerKeyedMember.new(key: key, value: values[key]) },
        diagnostics: ["independent keyed member edits were merged by key"]
      )
    end

    def conformance_family_entries(manifest, family)
      families = manifest.fetch(:families, {})
      (families[family.to_sym] || families[family.to_s] || []).map { |entry| deep_dup(entry) }
    end

    def conformance_fixture_path(manifest, family, role)
      entry = conformance_family_entries(manifest, family).find { |candidate| candidate[:role] == role }
      entry && deep_dup(entry[:path])
    end

    def conformance_family_feature_profile_path(manifest, family)
      entry = manifest.fetch(:family_feature_profiles, []).find { |candidate| candidate[:family] == family.to_s }
      entry && deep_dup(entry[:path])
    end

    def parse_compact_ruleset(source)
      ruleset = { directives: [], comments: [] }
      diagnostics = []
      seen_directives = {}
      seen_repeatable_keys = {}

      source.to_s.split("\n").each_with_index do |raw_line, index|
        line_number = index + 1
        line = raw_line.strip
        next if line.empty?

        if line.start_with?("#")
          ruleset[:comments] << line
          next
        end

        name, *arguments = line.split(/\s+/)
        path = line_number.to_s
        unless compact_ruleset_identifier?(name)
          diagnostics << compact_ruleset_diagnostic("invalid directive token #{name.inspect}", path)
          next
        end
        unless compact_ruleset_known_directive?(name)
          diagnostics << compact_ruleset_diagnostic("unknown directive #{name.inspect}", path)
          next
        end
        if arguments.empty?
          diagnostics << compact_ruleset_diagnostic("directive #{name.inspect} requires at least one argument", path)
          next
        end

        arguments.each do |argument|
          next if %w[true false].include?(argument) || compact_ruleset_identifier?(argument) || compact_ruleset_token?(argument)

          diagnostics << compact_ruleset_diagnostic("invalid argument token #{argument.inspect}", path)
        end

        if COMPACT_RULESET_SINGLETON_DIRECTIVES.include?(name) && seen_directives.key?(name)
          diagnostics << compact_ruleset_diagnostic(
            "repeated singleton directive #{name.inspect} first seen on line #{seen_directives.fetch(name)}",
            path
          )
        end
        if COMPACT_RULESET_REPEATABLE_KEYED_DIRECTIVES.include?(name)
          key = compact_ruleset_repeatable_key(name, arguments)
          diagnostics << compact_ruleset_diagnostic("repeated #{name.inspect} key #{arguments.fetch(0).inspect}", path) if seen_repeatable_keys[key]
          seen_repeatable_keys[key] = true
        end
        diagnostics << compact_ruleset_diagnostic("unknown read value #{arguments.fetch(0).inspect}", path) if name == "read" && !COMPACT_RULESET_READ_VALUES.include?(arguments.fetch(0))
        diagnostics << compact_ruleset_diagnostic("unknown attach value #{arguments.fetch(0).inspect}", path) if name == "attach" && !COMPACT_RULESET_ATTACH_VALUES.include?(arguments.fetch(0))

        seen_directives[name] = line_number
        ruleset[:directives] << { name: name, arguments: arguments, line: line_number }
      end

      COMPACT_RULESET_REQUIRED_DIRECTIVES.each do |required|
        diagnostics << compact_ruleset_diagnostic("missing required directive #{required.inspect}") unless seen_directives.key?(required)
      end

      diagnostics.empty? ? { ok: true, diagnostics: [], analysis: ruleset, policies: [] } : { ok: false, diagnostics: diagnostics, policies: [] }
    end

    def compact_ruleset_feature_profile(ruleset)
      profile = {
        format: "",
        owners: "",
        match: "",
        read: "",
        attach: "",
        backends: [],
        node_roles: [],
        atomic_nodes: [],
        child_groups: [],
        capabilities: [],
        logical_owners: [],
        repairs: [],
        surfaces: [],
        delegates: []
      }

      ruleset.fetch(:directives, []).each do |directive|
        arguments = directive.fetch(:arguments, [])
        next if arguments.empty?

        case directive.fetch(:name)
        when "format"
          profile[:format] = arguments.fetch(0)
        when "owners"
          profile[:owners] = arguments.fetch(0)
        when "match"
          profile[:match] = arguments.fetch(0)
        when "read"
          profile[:read] = arguments.fetch(0)
        when "attach"
          profile[:attach] = arguments.fetch(0)
        when "comment_style"
          profile[:comment_style] = arguments.fetch(0)
        when "render"
          profile[:render] = arguments.fetch(0)
        when "render_strategy"
          profile[:render_strategy] = arguments.fetch(0)
        when "backend"
          profile[:backends] << { backend: arguments.fetch(0), support: arguments.fetch(1) } if arguments.length > 1
        when "node_role"
          profile[:node_roles] << { selector: arguments.fetch(0), role: arguments.fetch(1) } if arguments.length > 1
        when "atomic"
          profile[:atomic_nodes] << { selector: arguments.fetch(0), atomic: arguments.fetch(1) == "true" } if arguments.length > 1
        when "child_group"
          if arguments.length > 2
            profile[:child_groups] << {
              parent_selector: arguments.fetch(0),
              name: arguments.fetch(1),
              policy: arguments.fetch(2)
            }
          end
        when "capability"
          profile[:capabilities] << { name: arguments.fetch(0), value: arguments.fetch(1) } if arguments.length > 1
        when "logical_owner"
          profile[:logical_owners] << { name: arguments.fetch(0), value: arguments.fetch(1) } if arguments.length > 1
        when "repair"
          profile[:repairs] << { name: arguments.fetch(0), value: arguments.fetch(1) } if arguments.length > 1
        when "surface"
          profile[:surfaces] << { name: arguments.fetch(0), selector: arguments.fetch(1) } if arguments.length > 1
        when "delegate"
          profile[:delegates] << { surface: arguments.fetch(0), policy: arguments.fetch(1) } if arguments.length > 1
        end
      end

      profile
    end

    def normalize_template_source_path(path)
      return path.delete_suffix(".no-osc.example") if path.end_with?(".no-osc.example")
      return path.delete_suffix(".example") if path.end_with?(".example")

      path
    end

    def compact_ruleset_repeatable_key(name, arguments)
      return [name, arguments.fetch(0), arguments.fetch(1)] if name == "child_group" && arguments.length > 1

      [name, arguments.fetch(0)]
    end

    def classify_template_target_path(path)
      normalized_path = path.to_s.delete_prefix("./")
      base = File.basename(normalized_path)
      lower_path = normalized_path.downcase
      lower_base = base.downcase

      return template_target_classification(path, "ruby", "ruby", "ruby") if normalized_path == ".git-hooks/commit-msg"
      return template_target_classification(path, "bash", "bash", "bash") if normalized_path == ".git-hooks/prepare-commit-msg"

      case base
      when "Gemfile", "Appraisal.root.gemfile"
        return template_target_classification(path, "gemfile", "ruby", "ruby")
      when "Appraisals"
        return template_target_classification(path, "appraisals", "ruby", "ruby")
      when "Rakefile", ".simplecov"
        return template_target_classification(path, "ruby", "ruby", "ruby")
      when ".envrc"
        return template_target_classification(path, "bash", "bash", "bash")
      when ".tool-versions"
        return template_target_classification(path, "tool_versions", "text", "tool_versions")
      when "CITATION.cff"
        return template_target_classification(path, "yaml", "yaml", "yaml")
      end

      return template_target_classification(path, "gemspec", "ruby", "ruby") if lower_base.end_with?(".gemspec")
      return template_target_classification(path, "gemfile", "ruby", "ruby") if lower_base.end_with?(".gemfile")
      return template_target_classification(path, "ruby", "ruby", "ruby") if lower_base.end_with?(".rb", ".rake")
      return template_target_classification(path, "yaml", "yaml", "yaml") if lower_path.end_with?(".yml", ".yaml")
      return template_target_classification(path, "markdown", "markdown", "markdown") if lower_path.end_with?(".md", ".markdown")
      return template_target_classification(path, "bash", "bash", "bash") if lower_path.end_with?(".sh", ".bash")
      return template_target_classification(path, "dotenv", "dotenv", "dotenv") if lower_base == ".env" || lower_base.start_with?(".env.")
      return template_target_classification(path, "json", "json", "jsonc") if lower_path.end_with?(".jsonc")
      return template_target_classification(path, "json", "json", "json") if lower_path.end_with?(".json")
      return template_target_classification(path, "toml", "toml", "toml") if lower_path.end_with?(".toml")
      return template_target_classification(path, "rbs", "rbs", "rbs") if lower_path.end_with?(".rbs")

      template_target_classification(path, "text", "text", "text")
    end

    def resolve_template_destination_path(path, context = {})
      case path.to_s
      when ".kettle-jem.yml"
        nil
      when ".env.local"
        ".env.local.example"
      when "gem.gemspec"
        project_name = context[:project_name] || context["project_name"]
        return "#{project_name.to_s.strip}.gemspec" unless project_name.to_s.strip.empty?

        path
      else
        path
      end
    end

    def default_template_token_config
      {
        pre: TEMPLATE_TOKEN_CONFIG.pre,
        post: TEMPLATE_TOKEN_CONFIG.post,
        separators: TEMPLATE_TOKEN_CONFIG.separators,
        min_segments: TEMPLATE_TOKEN_CONFIG.min_segments,
        max_segments: TEMPLATE_TOKEN_CONFIG.max_segments,
        segment_pattern: TEMPLATE_TOKEN_CONFIG.segment_pattern
      }
    end

    def template_token_keys(content, config = nil)
      document = Token::Resolver::Document.new(content.to_s, config: token_resolver_config(config))
      document.token_keys
    end

    def unresolved_template_token_keys(content, replacements = {}, config = nil)
      replacement_keys = normalize_template_replacements(replacements)
      template_token_keys(content, config).reject { |key| replacement_keys.key?(key) }
    end

    def resolve_template_tokens(content, replacements = {}, config = nil)
      resolver = Token::Resolver::Resolve.new(on_missing: :keep)
      document = Token::Resolver::Document.new(content.to_s, config: token_resolver_config(config))
      resolver.resolve(document, normalize_template_replacements(replacements))
    end

    def select_template_strategy(path, default_strategy = "merge", overrides = [])
      normalized_path = path.to_s.delete_prefix("./")
      override = overrides.find do |entry|
        candidate = entry[:path] || entry["path"]
        candidate.to_s.delete_prefix("./") == normalized_path
      end
      return (override[:strategy] || override["strategy"]).to_s if override

      default_strategy.to_s
    end

    def plan_template_entries(template_source_paths, context = {}, default_strategy = "merge", overrides = [])
      template_source_paths.map do |template_source_path|
        logical_destination_path = normalize_template_source_path(template_source_path)
        destination_path = resolve_template_destination_path(logical_destination_path, context)
        strategy = select_template_strategy(logical_destination_path, default_strategy, overrides)
        {
          template_source_path: template_source_path,
          logical_destination_path: logical_destination_path,
          destination_path: destination_path,
          classification: classify_template_target_path(logical_destination_path),
          strategy: strategy,
          action: destination_path.nil? ? "omit" : strategy
        }
      end
    end

    def enrich_template_plan_entries(entries, existing_destination_paths)
      existing = existing_destination_paths.each_with_object({}) { |path, memo| memo[path] = true }
      entries.map do |entry|
        destination_path = entry[:destination_path] || entry["destination_path"]
        strategy = (entry[:strategy] || entry["strategy"]).to_s
        destination_exists = destination_path ? existing.fetch(destination_path, false) : false
        write_action = if destination_path.nil?
          "omit"
        elsif strategy == "keep_destination"
          "keep"
        elsif destination_exists
          "update"
        else
          "create"
        end

        deep_dup(entry).merge(
          destination_exists: destination_exists,
          write_action: write_action
        )
      end
    end

    def enrich_template_plan_entries_with_token_state(entries, template_contents, replacements, config = nil)
      normalized_replacements = normalize_template_replacements(replacements)

      entries.map do |entry|
        source_path = entry[:template_source_path] || entry["template_source_path"]
        destination_path = entry[:destination_path] || entry["destination_path"]
        strategy = (entry[:strategy] || entry["strategy"]).to_s
        content = template_contents[source_path] || template_contents[source_path.to_s] ||
          template_contents[source_path.to_sym] || ""
        token_keys = template_token_keys(content, config)
        unresolved_token_keys = token_keys.reject { |key| normalized_replacements.key?(key) }
        token_resolution_required = !destination_path.nil? && strategy != "keep_destination" && strategy != "raw_copy"
        blocked = token_resolution_required && !unresolved_token_keys.empty?

        deep_dup(entry).merge(
          token_keys: token_keys,
          unresolved_token_keys: unresolved_token_keys,
          token_resolution_required: token_resolution_required,
          blocked: blocked,
          block_reason: blocked ? "unresolved_tokens" : nil
        )
      end
    end

    def prepare_template_entries(entries, template_contents, replacements, config = nil)
      entries.map do |entry|
        source_path = entry[:template_source_path] || entry["template_source_path"]
        template_content = template_contents[source_path] || template_contents[source_path.to_s] ||
          template_contents[source_path.to_sym] || ""

        if entry[:blocked] || entry["blocked"]
          next deep_dup(entry).merge(
            template_content: template_content,
            prepared_template_content: nil,
            preparation_action: "blocked"
          )
        end

        token_resolution_required = entry[:token_resolution_required]
        token_resolution_required = entry["token_resolution_required"] if token_resolution_required.nil?
        prepared_template_content = if token_resolution_required
          resolve_template_tokens(template_content, replacements, config)
        else
          template_content
        end

        deep_dup(entry).merge(
          template_content: template_content,
          prepared_template_content: prepared_template_content,
          preparation_action: token_resolution_required ? "resolve_tokens" : "pass_through"
        )
      end
    end

    def plan_template_execution(entries, destination_contents)
      entries.map do |entry|
        destination_path = entry[:destination_path] || entry["destination_path"]
        strategy = (entry[:strategy] || entry["strategy"]).to_s
        write_action = (entry[:write_action] || entry["write_action"]).to_s
        blocked = entry[:blocked]
        blocked = entry["blocked"] if blocked.nil?
        destination_content = if destination_path
          destination_contents[destination_path] || destination_contents[destination_path.to_s] ||
            destination_contents[destination_path.to_sym]
        end

        execution_action = if blocked
          "blocked"
        elsif destination_path.nil?
          "omit"
        elsif write_action == "keep"
          "keep"
        elsif strategy == "raw_copy"
          "raw_copy"
        elsif strategy == "accept_template"
          "write_prepared_content"
        else
          "merge_prepared_content"
        end

        deep_dup(entry).merge(
          execution_action: execution_action,
          ready: !%w[blocked omit keep].include?(execution_action),
          destination_content: destination_content
        )
      end
    end

    def plan_template_tree_execution(template_source_paths, template_contents, existing_destination_paths,
      destination_contents, context = {}, default_strategy = "merge", overrides = [], replacements = {}, config = nil)
      planned_entries = plan_template_entries(template_source_paths, context, default_strategy, overrides)
      stateful_entries = enrich_template_plan_entries(planned_entries, existing_destination_paths)
      token_state_entries = enrich_template_plan_entries_with_token_state(
        stateful_entries,
        template_contents,
        replacements,
        config
      )
      prepared_entries = prepare_template_entries(token_state_entries, template_contents, replacements, config)

      plan_template_execution(prepared_entries, destination_contents)
    end

    def preview_template_execution(entries)
      result = {
        result_files: {},
        created_paths: [],
        updated_paths: [],
        kept_paths: [],
        blocked_paths: [],
        omitted_paths: []
      }

      entries.each do |entry|
        destination_path = entry[:destination_path] || entry["destination_path"]
        execution_action = (entry[:execution_action] || entry["execution_action"]).to_s
        destination_exists = entry[:destination_exists]
        destination_exists = entry["destination_exists"] if destination_exists.nil?
        prepared_template_content = entry[:prepared_template_content] || entry["prepared_template_content"]
        destination_content = entry[:destination_content] || entry["destination_content"]

        case execution_action
        when "blocked"
          result[:blocked_paths] << destination_path if destination_path
        when "omit"
          result[:omitted_paths] << (entry[:logical_destination_path] || entry["logical_destination_path"])
        when "keep"
          next unless destination_path && !destination_content.nil?

          result[:result_files][destination_path] = destination_content
          result[:kept_paths] << destination_path
        when "raw_copy", "write_prepared_content"
          next unless destination_path && !prepared_template_content.nil?

          result[:result_files][destination_path] = prepared_template_content
          if destination_exists && destination_content == prepared_template_content
            result[:kept_paths] << destination_path
          else
            (destination_exists ? result[:updated_paths] : result[:created_paths]) << destination_path
          end
        when "merge_prepared_content"
          next unless destination_path && !prepared_template_content.nil? && destination_content.nil?

          result[:result_files][destination_path] = prepared_template_content
          (destination_exists ? result[:updated_paths] : result[:created_paths]) << destination_path
        end
      end

      result
    end

    def apply_template_execution(entries)
      result = {
        result_files: {},
        created_paths: [],
        updated_paths: [],
        kept_paths: [],
        blocked_paths: [],
        omitted_paths: [],
        diagnostics: []
      }

      entries.each do |entry|
        destination_path = entry[:destination_path] || entry["destination_path"]
        execution_action = (entry[:execution_action] || entry["execution_action"]).to_s
        destination_exists = entry[:destination_exists]
        destination_exists = entry["destination_exists"] if destination_exists.nil?
        prepared_template_content = entry[:prepared_template_content] || entry["prepared_template_content"]
        destination_content = entry[:destination_content] || entry["destination_content"]

        case execution_action
        when "blocked"
          result[:blocked_paths] << destination_path if destination_path
        when "omit"
          result[:omitted_paths] << (entry[:logical_destination_path] || entry["logical_destination_path"])
        when "keep"
          next unless destination_path && !destination_content.nil?

          result[:result_files][destination_path] = destination_content
          result[:kept_paths] << destination_path
        when "raw_copy", "write_prepared_content"
          next unless destination_path && !prepared_template_content.nil?

          record_template_apply_output(result, destination_path, destination_exists, destination_content,
            prepared_template_content)
        when "merge_prepared_content"
          next unless destination_path && !prepared_template_content.nil?

          if destination_content.nil?
            record_template_apply_output(result, destination_path, destination_exists, destination_content,
              prepared_template_content)
            next
          end

          merge_result = yield(deep_dup(entry))
          result[:diagnostics].concat(Array(merge_result[:diagnostics] || merge_result["diagnostics"]))
          ok = merge_result[:ok]
          ok = merge_result["ok"] if ok.nil?
          output = merge_result[:output]
          output = merge_result["output"] if output.nil?
          unless ok && !output.nil?
            result[:blocked_paths] << destination_path
            next
          end

          record_template_apply_output(result, destination_path, destination_exists, destination_content, output)
        end
      end

      result
    end

    def evaluate_template_tree_convergence(template_source_paths, template_contents, destination_contents,
      context = {}, default_strategy = "merge", overrides = [], replacements = {}, config = nil)
      execution_plan = plan_template_tree_execution(
        template_source_paths,
        template_contents,
        destination_contents.keys.sort,
        destination_contents,
        context,
        default_strategy,
        overrides,
        replacements,
        config
      )
      pending_paths = execution_plan.filter_map do |entry|
        blocked = entry[:blocked]
        blocked = entry["blocked"] if blocked.nil?
        if blocked
          next entry[:destination_path] || entry["destination_path"] ||
            entry[:logical_destination_path] || entry["logical_destination_path"]
        end

        ready = entry[:ready]
        ready = entry["ready"] if ready.nil?
        next unless ready

        destination_content = entry[:destination_content]
        destination_content = entry["destination_content"] if destination_content.nil?
        prepared_template_content = entry[:prepared_template_content]
        prepared_template_content = entry["prepared_template_content"] if prepared_template_content.nil?
        next if !destination_content.nil? &&
          !prepared_template_content.nil? &&
          destination_content == prepared_template_content

        entry[:destination_path] || entry["destination_path"] ||
          entry[:logical_destination_path] || entry["logical_destination_path"]
      end

      {
        converged: pending_paths.empty?,
        pending_paths: pending_paths
      }
    end

    def run_template_tree_execution(template_source_paths, template_contents, destination_contents,
      context = {}, default_strategy = "merge", overrides = [], replacements = {}, config = nil, &merge_prepared_content)
      execution_plan = plan_template_tree_execution(
        template_source_paths,
        template_contents,
        destination_contents.keys.sort,
        destination_contents,
        context,
        default_strategy,
        overrides,
        replacements,
        config
      )

      {
        execution_plan: execution_plan,
        apply_result: apply_template_execution(execution_plan, &merge_prepared_content)
      }
    end

    def read_relative_file_tree(root)
      root = Pathname(root).expand_path
      return {} unless root.exist?
      raise ArgumentError, "#{root} is not a directory" unless root.directory?

      root.find.each_with_object({}) do |path, files|
        next if path.directory?

        files[path.relative_path_from(root).to_s] = path.read
      end
    end

    def write_relative_file_tree(root, files)
      root = Pathname(root).expand_path
      root.mkpath

      files.keys.sort.each do |relative_path|
        path = root.join(*relative_path.split("/"))
        path.dirname.mkpath
        path.write(files.fetch(relative_path))
      end
    end

    def run_template_tree_execution_from_directories(template_root, destination_root,
      context = {}, default_strategy = "merge", overrides = [], replacements = {}, config = nil, &merge_prepared_content)
      template_contents = read_relative_file_tree(template_root)
      destination_contents = read_relative_file_tree(destination_root)

      run_template_tree_execution(
        template_contents.keys.sort,
        template_contents,
        destination_contents,
        context,
        default_strategy,
        overrides,
        replacements,
        config,
        &merge_prepared_content
      )
    end

    def plan_template_tree_execution_from_directories(template_root, destination_root,
      context = {}, default_strategy = "merge", overrides = [], replacements = {}, config = nil)
      template_contents = read_relative_file_tree(template_root)
      destination_contents = read_relative_file_tree(destination_root)

      plan_template_tree_execution(
        template_contents.keys.sort,
        template_contents,
        destination_contents.keys.sort,
        destination_contents,
        context,
        default_strategy,
        overrides,
        replacements,
        config
      )
    end

    def apply_template_tree_execution_to_directory(template_root, destination_root,
      context = {}, default_strategy = "merge", overrides = [], replacements = {}, config = nil, &merge_prepared_content)
      run_result = run_template_tree_execution_from_directories(
        template_root,
        destination_root,
        context,
        default_strategy,
        overrides,
        replacements,
        config,
        &merge_prepared_content
      )

      files_to_write = {}
      Array(run_result.dig(:apply_result, :created_paths) || run_result.dig("apply_result", "created_paths")).each do |path|
        files_to_write[path] = run_result.dig(:apply_result, :result_files, path) ||
          run_result.dig("apply_result", "result_files", path)
      end
      Array(run_result.dig(:apply_result, :updated_paths) || run_result.dig("apply_result", "updated_paths")).each do |path|
        files_to_write[path] = run_result.dig(:apply_result, :result_files, path) ||
          run_result.dig("apply_result", "result_files", path)
      end
      write_relative_file_tree(destination_root, files_to_write)

      run_result
    end

    def report_template_tree_run(result)
      created = Array(result.dig(:apply_result, :created_paths) || result.dig("apply_result", "created_paths"))
      updated = Array(result.dig(:apply_result, :updated_paths) || result.dig("apply_result", "updated_paths"))
      kept = Array(result.dig(:apply_result, :kept_paths) || result.dig("apply_result", "kept_paths"))
      blocked = Array(result.dig(:apply_result, :blocked_paths) || result.dig("apply_result", "blocked_paths"))
      omitted = Array(result.dig(:apply_result, :omitted_paths) || result.dig("apply_result", "omitted_paths"))

      entries = Array(result[:execution_plan] || result["execution_plan"]).map do |entry|
        destination_path = entry[:destination_path] || entry["destination_path"]
        logical_destination_path = entry[:logical_destination_path] || entry["logical_destination_path"]
        execution_action = (entry[:execution_action] || entry["execution_action"]).to_s
        status = if execution_action == "omit" || omitted.include?(logical_destination_path)
          "omitted"
        elsif destination_path && blocked.include?(destination_path)
          "blocked"
        elsif destination_path && kept.include?(destination_path)
          "kept"
        elsif destination_path && updated.include?(destination_path)
          "updated"
        else
          "created"
        end

        {
          template_source_path: entry[:template_source_path] || entry["template_source_path"],
          logical_destination_path: logical_destination_path,
          destination_path: destination_path,
          execution_action: execution_action,
          status: status
        }
      end

      {
        entries: entries,
        summary: {
          created: entries.count { |entry| entry[:status] == "created" },
          updated: entries.count { |entry| entry[:status] == "updated" },
          kept: entries.count { |entry| entry[:status] == "kept" },
          blocked: entries.count { |entry| entry[:status] == "blocked" },
          omitted: entries.count { |entry| entry[:status] == "omitted" }
        }
      }
    end

    def report_template_directory_apply(result)
      run_report = report_template_tree_run(result)
      created = Array(result.dig(:apply_result, :created_paths) || result.dig("apply_result", "created_paths"))
      updated = Array(result.dig(:apply_result, :updated_paths) || result.dig("apply_result", "updated_paths"))

      entries = run_report[:entries].map do |entry|
        destination_path = entry[:destination_path] || entry["destination_path"]
        written = destination_path && (created.include?(destination_path) || updated.include?(destination_path))

        {
          template_source_path: entry[:template_source_path] || entry["template_source_path"],
          logical_destination_path: entry[:logical_destination_path] || entry["logical_destination_path"],
          destination_path: destination_path,
          execution_action: entry[:execution_action] || entry["execution_action"],
          status: entry[:status] || entry["status"],
          written: !!written
        }
      end

      {
        entries: entries,
        summary: {
          created: entries.count { |entry| entry[:status] == "created" },
          updated: entries.count { |entry| entry[:status] == "updated" },
          kept: entries.count { |entry| entry[:status] == "kept" },
          blocked: entries.count { |entry| entry[:status] == "blocked" },
          omitted: entries.count { |entry| entry[:status] == "omitted" },
          written: entries.count { |entry| entry[:written] }
        }
      }
    end

    def report_template_directory_plan(entries)
      report_entries = Array(entries).map do |entry|
        execution_action = (entry[:execution_action] || entry["execution_action"]).to_s
        write_action = (entry[:write_action] || entry["write_action"]).to_s
        status, previewable =
          case execution_action
          when "blocked"
            ["blocked", false]
          when "omit"
            ["omitted", true]
          when "keep"
            ["keep", true]
          when "raw_copy", "write_prepared_content"
            [write_action == "create" ? "create" : "update", true]
          else
            [write_action == "create" ? "create" : "update", write_action == "create"]
          end

        {
          template_source_path: entry[:template_source_path] || entry["template_source_path"],
          logical_destination_path: entry[:logical_destination_path] || entry["logical_destination_path"],
          destination_path: entry[:destination_path] || entry["destination_path"],
          execution_action: execution_action,
          write_action: write_action,
          status: status,
          previewable: previewable
        }
      end

      {
        entries: report_entries,
        summary: {
          create: report_entries.count { |entry| entry[:status] == "create" },
          update: report_entries.count { |entry| entry[:status] == "update" },
          keep: report_entries.count { |entry| entry[:status] == "keep" },
          blocked: report_entries.count { |entry| entry[:status] == "blocked" },
          omitted: report_entries.count { |entry| entry[:status] == "omitted" }
        }
      }
    end

    def report_template_directory_runner(entries, result = nil)
      report = {
        plan_report: report_template_directory_plan(entries),
        preview: preview_template_execution(entries),
        run_report: nil,
        apply_report: nil
      }
      return report if result.nil?

      report[:run_report] = report_template_tree_run(result)
      report[:apply_report] = report_template_directory_apply(result)
      report
    end

    def record_template_apply_output(result, destination_path, destination_exists, destination_content, output)
      result[:result_files][destination_path] = output
      if destination_exists && destination_content == output
        result[:kept_paths] << destination_path
      elsif destination_exists
        result[:updated_paths] << destination_path
      else
        result[:created_paths] << destination_path
      end
    end

    def conformance_suite_definition(manifest, selector)
      manifest.fetch(:suite_descriptors, []).find do |definition|
        conformance_suite_selectors_equal?(
          { kind: definition[:kind], subject: deep_dup(definition[:subject]) },
          selector
        )
      end&.then { |definition| deep_dup(definition) }
    end

    def token_resolver_config(config)
      normalized = default_template_token_config.merge(normalize_value(config || {}))
      Token::Resolver::Config.new(
        pre: normalized[:pre],
        post: normalized[:post],
        separators: normalized[:separators],
        min_segments: normalized[:min_segments],
        max_segments: normalized[:max_segments],
        segment_pattern: normalized[:segment_pattern]
      )
    end

    def normalize_template_replacements(replacements)
      (replacements || {}).each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

    def conformance_suite_selectors(manifest)
      manifest.fetch(:suite_descriptors, []).map do |definition|
        {
          kind: definition[:kind],
          subject: deep_dup(definition[:subject])
        }
      end.sort_by do |selector|
        [
          selector[:kind].to_s,
          selector.dig(:subject, :grammar).to_s,
          selector.dig(:subject, :variant).to_s
        ]
      end
    end

    def conformance_suite_descriptor_string(definition)
      JSON.generate(json_ready(definition))
    end

    def default_conformance_family_context(family_profile)
      { family_profile: deep_dup(family_profile) }
    end

    def review_request_id_for_family_context(family)
      "family_context:#{family}"
    end

    def conformance_review_host_hints(options)
      {
        interactive: options.fetch(:interactive, false),
        require_explicit_contexts: options.fetch(:require_explicit_contexts, false)
      }
    end

    def surface_owner_ref(kind:, address:)
      {
        kind: kind.to_s,
        address: address
      }
    end

    def surface_span(start_line:, end_line:)
      {
        start_line: start_line,
        end_line: end_line
      }
    end

    def discovered_surface(surface_kind:, effective_language:, address:, owner:, declared_language: nil,
      parent_address: nil, span: nil, reconstruction_strategy:, metadata: nil)
      surface = {
        surface_kind: surface_kind.to_s,
        effective_language: effective_language.to_s,
        address: address,
        owner: deep_dup(owner),
        reconstruction_strategy: reconstruction_strategy.to_s
      }
      surface[:declared_language] = declared_language.to_s if declared_language
      surface[:parent_address] = parent_address if parent_address
      surface[:span] = deep_dup(span) if span
      surface[:metadata] = deep_dup(metadata) if metadata
      surface
    end

    def delegated_child_operation(operation_id:, parent_operation_id:, requested_strategy:, language_chain:, surface:)
      {
        operation_id: operation_id,
        parent_operation_id: parent_operation_id,
        requested_strategy: requested_strategy.to_s,
        language_chain: deep_dup(language_chain),
        surface: deep_dup(surface)
      }
    end

    def structured_edit_structure_profile(owner_scope:, owner_selector:, known_owner_selector:,
      supported_comment_regions:, owner_selector_family: nil, metadata: nil)
      profile = {
        owner_scope: owner_scope.to_s,
        owner_selector: owner_selector.to_s,
        known_owner_selector: known_owner_selector ? true : false,
        supported_comment_regions: deep_dup(supported_comment_regions).map(&:to_s)
      }
      profile[:owner_selector_family] = owner_selector_family.to_s if owner_selector_family
      profile[:metadata] = deep_dup(metadata) if metadata
      profile
    end

    def structured_edit_selection_profile(owner_scope:, owner_selector:, selector_kind:, selection_intent:,
      known_selection_intent:, include_trailing_gap:, comment_anchored:, owner_selector_family: nil,
      selection_intent_family: nil, comment_region: nil, metadata: nil)
      profile = {
        owner_scope: owner_scope.to_s,
        owner_selector: owner_selector.to_s,
        selector_kind: selector_kind.to_s,
        selection_intent: selection_intent.to_s,
        known_selection_intent: known_selection_intent ? true : false,
        include_trailing_gap: include_trailing_gap ? true : false,
        comment_anchored: comment_anchored ? true : false
      }
      profile[:owner_selector_family] = owner_selector_family.to_s if owner_selector_family
      profile[:selection_intent_family] = selection_intent_family.to_s if selection_intent_family
      profile[:comment_region] = comment_region.nil? ? nil : comment_region.to_s
      profile[:metadata] = deep_dup(metadata) if metadata
      profile
    end

    def structured_edit_target_selection(selector_kind:, selection_intent:, known_selection_intent:,
      include_trailing_gap:, comment_anchored:, selection_intent_family: nil, comment_region: nil,
      metadata: nil)
      selection = {
        selector_kind: selector_kind.to_s,
        selection_intent: selection_intent.to_s,
        known_selection_intent: known_selection_intent ? true : false,
        include_trailing_gap: include_trailing_gap ? true : false,
        comment_anchored: comment_anchored ? true : false
      }
      selection[:selection_intent_family] = selection_intent_family.to_s if selection_intent_family
      selection[:comment_region] = comment_region.nil? ? nil : comment_region.to_s
      selection[:metadata] = deep_dup(metadata) if metadata
      selection
    end

    def structured_edit_match_profile(start_boundary:, end_boundary:, payload_kind:, known_start_boundary:,
      known_end_boundary:, known_payload_kind:, comment_anchored:, trailing_gap_extended:,
      start_boundary_family: nil, end_boundary_family: nil, payload_family: nil, metadata: nil)
      profile = {
        start_boundary: start_boundary.to_s,
        known_start_boundary: known_start_boundary ? true : false,
        end_boundary: end_boundary.to_s,
        known_end_boundary: known_end_boundary ? true : false,
        payload_kind: payload_kind.to_s,
        known_payload_kind: known_payload_kind ? true : false,
        comment_anchored: comment_anchored ? true : false,
        trailing_gap_extended: trailing_gap_extended ? true : false
      }
      profile[:start_boundary_family] = start_boundary_family.to_s if start_boundary_family
      profile[:end_boundary_family] = end_boundary_family.to_s if end_boundary_family
      profile[:payload_family] = payload_family.to_s if payload_family
      profile[:metadata] = deep_dup(metadata) if metadata
      profile
    end

    def structured_edit_target_match(start_boundary:, end_boundary:, payload_kind:, known_start_boundary:,
      known_end_boundary:, known_payload_kind:, comment_anchored:, trailing_gap_extended:,
      start_boundary_family: nil, end_boundary_family: nil, payload_family: nil, metadata: nil)
      structured_edit_match_profile(
        start_boundary: start_boundary,
        end_boundary: end_boundary,
        payload_kind: payload_kind,
        known_start_boundary: known_start_boundary,
        known_end_boundary: known_end_boundary,
        known_payload_kind: known_payload_kind,
        comment_anchored: comment_anchored,
        trailing_gap_extended: trailing_gap_extended,
        start_boundary_family: start_boundary_family,
        end_boundary_family: end_boundary_family,
        payload_family: payload_family,
        metadata: metadata
      )
    end

    def structured_edit_operation_profile(operation_kind:, known_operation_kind:, source_requirement:,
      destination_requirement:, replacement_source:, captures_source_text:, supports_if_missing:,
      operation_family: nil, metadata: nil)
      profile = {
        operation_kind: operation_kind.to_s,
        known_operation_kind: known_operation_kind ? true : false,
        source_requirement: source_requirement.to_s,
        destination_requirement: destination_requirement.to_s,
        replacement_source: replacement_source.to_s,
        captures_source_text: captures_source_text ? true : false,
        supports_if_missing: supports_if_missing ? true : false
      }
      profile[:operation_family] = operation_family.to_s if operation_family
      profile[:metadata] = deep_dup(metadata) if metadata
      profile
    end

    def structured_edit_destination_profile(resolution_kind:, resolution_source:, anchor_boundary:,
      resolution_family:, resolution_source_family:, anchor_boundary_family:, known_resolution_kind:,
      known_resolution_source:, known_anchor_boundary:, used_if_missing:, metadata: nil)
      profile = {
        resolution_kind: resolution_kind.to_s,
        resolution_source: resolution_source.to_s,
        anchor_boundary: anchor_boundary.to_s,
        resolution_family: resolution_family.to_s,
        resolution_source_family: resolution_source_family.to_s,
        anchor_boundary_family: anchor_boundary_family.to_s,
        known_resolution_kind: known_resolution_kind ? true : false,
        known_resolution_source: known_resolution_source ? true : false,
        known_anchor_boundary: known_anchor_boundary ? true : false,
        used_if_missing: used_if_missing ? true : false
      }
      profile[:metadata] = deep_dup(metadata) if metadata
      profile
    end

    def structured_edit_request(operation_kind:, content:, source_label:, target_selector: nil,
      target_selector_family: nil, destination_selector: nil, destination_selector_family: nil,
      payload_text: nil, if_missing: nil, callable_destination: nil, target_selection: nil,
      target_match: nil, metadata: nil)
      request = {
        operation_kind: operation_kind.to_s,
        content: content.to_s,
        source_label: source_label.to_s
      }
      request[:target_selector] = target_selector.to_s if target_selector
      request[:target_selector_family] = target_selector_family.to_s if target_selector_family
      request[:target_selection] = deep_dup(target_selection) if target_selection
      request[:target_match] = deep_dup(target_match) if target_match
      request[:destination_selector] = destination_selector.to_s if destination_selector
      request[:destination_selector_family] = destination_selector_family.to_s if destination_selector_family
      request[:payload_text] = payload_text.to_s unless payload_text.nil?
      request[:if_missing] = if_missing.to_s unless if_missing.nil?
      request[:callable_destination] = deep_dup(callable_destination) if callable_destination
      request[:metadata] = deep_dup(metadata) if metadata
      request
    end

    def structured_edit_result(operation_kind:, updated_content:, changed:, operation_profile:,
      captured_text: nil, match_count: nil, destination_profile: nil, metadata: nil)
      result = {
        operation_kind: operation_kind.to_s,
        updated_content: updated_content.to_s,
        changed: changed ? true : false,
        operation_profile: deep_dup(operation_profile)
      }
      result[:captured_text] = captured_text.to_s unless captured_text.nil?
      result[:match_count] = match_count.to_i unless match_count.nil?
      result[:destination_profile] = deep_dup(destination_profile) if destination_profile
      result[:metadata] = deep_dup(metadata) if metadata
      result
    end

    def structured_edit_application(request:, result:, metadata: nil)
      application = {
        request: deep_dup(request),
        result: deep_dup(result)
      }
      application[:metadata] = deep_dup(metadata) if metadata
      application
    end

    def structured_edit_application_envelope(application)
      {
        kind: "structured_edit_application",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        application: deep_dup(application)
      }
    end

    def import_structured_edit_application_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_application envelope kind." }] unless envelope[:kind] == "structured_edit_application"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_application envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:application]), nil]
    end

    def structured_edit_request_envelope(request)
      {
        kind: "structured_edit_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        request: deep_dup(request)
      }
    end

    def import_structured_edit_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_request envelope kind." }] unless envelope[:kind] == "structured_edit_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:request]), nil]
    end

    def structured_edit_execution_report(application:, provider_family:, diagnostics:, provider_backend: nil, metadata: nil)
      report = {
        application: deep_dup(application),
        provider_family: provider_family.to_s,
        diagnostics: deep_dup(diagnostics)
      }
      report[:provider_backend] = provider_backend.to_s if provider_backend
      report[:metadata] = deep_dup(metadata) if metadata
      report
    end

    def structured_edit_crispr_example_parity_backend_note(backend:, scope:, notes:, metadata: nil)
      backend_note = {
        backend: backend.to_s,
        scope: scope.to_s,
        notes: Array(notes).map(&:to_s)
      }
      backend_note[:metadata] = deep_dup(metadata) if metadata
      backend_note
    end

    def structured_edit_crispr_example_parity_scenario(scenario:, family:, reproduced:, implementation_notes:,
      reference_backend: nil, backend_notes: nil, metadata: nil)
      parity_scenario = {
        scenario: scenario.to_s,
        family: family.to_s,
        reproduced: reproduced ? true : false,
        implementation_notes: Array(implementation_notes).map(&:to_s)
      }
      parity_scenario[:reference_backend] = reference_backend.to_s if reference_backend
      parity_scenario[:backend_notes] = deep_dup(backend_notes) if backend_notes
      parity_scenario[:metadata] = deep_dup(metadata) if metadata
      parity_scenario
    end

    def structured_edit_crispr_example_parity_report(scenarios:, remaining_gaps: nil, metadata: nil)
      report = {
        scenarios: deep_dup(scenarios)
      }
      report[:remaining_gaps] = Array(remaining_gaps).map(&:to_s) if remaining_gaps
      report[:metadata] = deep_dup(metadata) if metadata
      report
    end

    def structured_edit_kettle_jem_primitive_gap_report(reference_project:, scope:, product_target:,
      current_substrate:, required_primitives:, script_classifications:, non_goals: nil, next_slices: nil, metadata: nil)
      report = {
        reference_project: reference_project.to_s,
        scope: scope.to_s,
        product_target: product_target.to_s,
        current_substrate: deep_dup(current_substrate),
        required_primitives: deep_dup(required_primitives),
        script_classifications: deep_dup(script_classifications)
      }
      report[:non_goals] = Array(non_goals).map(&:to_s) if non_goals
      report[:next_slices] = Array(next_slices).map(&:to_s) if next_slices
      report[:metadata] = deep_dup(metadata) if metadata
      report
    end

    def structured_edit_provider_execution_request(request:, provider_family:, provider_backend: nil, metadata: nil)
      execution_request = {
        request: deep_dup(request),
        provider_family: provider_family.to_s
      }
      execution_request[:provider_backend] = provider_backend.to_s if provider_backend
      execution_request[:metadata] = deep_dup(metadata) if metadata
      execution_request
    end

    def structured_edit_provider_execution_request_envelope(execution_request)
      {
        kind: "structured_edit_provider_execution_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        execution_request: deep_dup(execution_request)
      }
    end

    def import_structured_edit_provider_execution_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:execution_request]), nil]
    end

    def structured_edit_provider_execution_plan(execution_request:, executor_resolution:, metadata: nil)
      execution_plan = {
        execution_request: deep_dup(execution_request),
        executor_resolution: deep_dup(executor_resolution)
      }
      execution_plan[:metadata] = deep_dup(metadata) if metadata
      execution_plan
    end

    def structured_edit_provider_execution_handoff(execution_plan:, execution_dispatch:, metadata: nil)
      execution_handoff = {
        execution_plan: deep_dup(execution_plan),
        execution_dispatch: deep_dup(execution_dispatch)
      }
      execution_handoff[:metadata] = deep_dup(metadata) if metadata
      execution_handoff
    end

    def structured_edit_provider_execution_handoff_envelope(execution_handoff)
      {
        kind: "structured_edit_provider_execution_handoff",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        execution_handoff: deep_dup(execution_handoff)
      }
    end

    def import_structured_edit_provider_execution_handoff_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_handoff envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_handoff"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_handoff envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:execution_handoff]), nil]
    end

    def structured_edit_provider_execution_invocation(execution_handoff:, metadata: nil)
      execution_invocation = {
        execution_handoff: deep_dup(execution_handoff)
      }
      execution_invocation[:metadata] = deep_dup(metadata) if metadata
      execution_invocation
    end

    def structured_edit_provider_execution_invocation_envelope(execution_invocation)
      {
        kind: "structured_edit_provider_execution_invocation",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        execution_invocation: deep_dup(execution_invocation)
      }
    end

    def import_structured_edit_provider_execution_invocation_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_invocation envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_invocation"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_invocation envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:execution_invocation]), nil]
    end

    def structured_edit_provider_batch_execution_invocation(invocations:, metadata: nil)
      batch_execution_invocation = {
        invocations: deep_dup(invocations)
      }
      batch_execution_invocation[:metadata] = deep_dup(metadata) if metadata
      batch_execution_invocation
    end

    def structured_edit_provider_batch_execution_invocation_envelope(batch_execution_invocation)
      {
        kind: "structured_edit_provider_batch_execution_invocation",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_execution_invocation: deep_dup(batch_execution_invocation)
      }
    end

    def import_structured_edit_provider_batch_execution_invocation_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_invocation envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_invocation"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_invocation envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_execution_invocation]), nil]
    end

    def structured_edit_provider_execution_run_result(execution_invocation:, outcome:, metadata: nil)
      execution_run_result = {
        execution_invocation: deep_dup(execution_invocation),
        outcome: deep_dup(outcome)
      }
      execution_run_result[:metadata] = deep_dup(metadata) if metadata
      execution_run_result
    end

    def structured_edit_provider_execution_run_result_envelope(execution_run_result)
      {
        kind: "structured_edit_provider_execution_run_result",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        execution_run_result: deep_dup(execution_run_result)
      }
    end

    def import_structured_edit_provider_execution_run_result_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_run_result envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_run_result"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_run_result envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:execution_run_result]), nil]
    end

    def structured_edit_provider_batch_execution_run_result(run_results:, metadata: nil)
      batch_execution_run_result = {
        run_results: deep_dup(run_results)
      }
      batch_execution_run_result[:metadata] = deep_dup(metadata) if metadata
      batch_execution_run_result
    end

    def structured_edit_provider_batch_execution_run_result_envelope(batch_execution_run_result)
      {
        kind: "structured_edit_provider_batch_execution_run_result",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_execution_run_result: deep_dup(batch_execution_run_result)
      }
    end

    def import_structured_edit_provider_batch_execution_run_result_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_run_result envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_run_result"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_run_result envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_execution_run_result]), nil]
    end

    def structured_edit_provider_execution_receipt(run_result:, provenance: nil, replay_bundle: nil, metadata: nil)
      execution_receipt = {
        run_result: deep_dup(run_result)
      }
      execution_receipt[:provenance] = deep_dup(provenance) if provenance
      execution_receipt[:replay_bundle] = deep_dup(replay_bundle) if replay_bundle
      execution_receipt[:metadata] = deep_dup(metadata) if metadata
      execution_receipt
    end

    def structured_edit_provider_execution_receipt_envelope(execution_receipt)
      {
        kind: "structured_edit_provider_execution_receipt",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        execution_receipt: deep_dup(execution_receipt)
      }
    end

    def import_structured_edit_provider_execution_receipt_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:execution_receipt]), nil]
    end

    def structured_edit_provider_batch_execution_receipt(receipts:, metadata: nil)
      batch_execution_receipt = {
        receipts: deep_dup(receipts)
      }
      batch_execution_receipt[:metadata] = deep_dup(metadata) if metadata
      batch_execution_receipt
    end

    def structured_edit_provider_batch_execution_receipt_envelope(batch_execution_receipt)
      {
        kind: "structured_edit_provider_batch_execution_receipt",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_execution_receipt: deep_dup(batch_execution_receipt)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_execution_receipt]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_request(execution_receipt:, replay_mode:, metadata: nil)
      replay_request = {
        execution_receipt: deep_dup(execution_receipt),
        replay_mode: replay_mode
      }
      replay_request[:metadata] = deep_dup(metadata) if metadata
      replay_request
    end

    def structured_edit_provider_execution_receipt_replay_request_envelope(receipt_replay_request)
      {
        kind: "structured_edit_provider_execution_receipt_replay_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_request: deep_dup(receipt_replay_request)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_request]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_request(requests:, metadata: nil)
      batch_receipt_replay_request = {
        requests: deep_dup(requests)
      }
      batch_receipt_replay_request[:metadata] = deep_dup(metadata) if metadata
      batch_receipt_replay_request
    end

    def structured_edit_provider_batch_execution_receipt_replay_request_envelope(batch_receipt_replay_request)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_request: deep_dup(batch_receipt_replay_request)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_request]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_application(receipt_replay_request:, run_result:, metadata: nil)
      replay_application = {
        receipt_replay_request: deep_dup(receipt_replay_request),
        run_result: deep_dup(run_result)
      }
      replay_application[:metadata] = deep_dup(metadata) if metadata
      replay_application
    end

    def structured_edit_provider_execution_receipt_replay_application_envelope(receipt_replay_application)
      {
        kind: "structured_edit_provider_execution_receipt_replay_application",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_application: deep_dup(receipt_replay_application)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_application_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_application envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_application"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_application envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_application]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_application(applications:, metadata: nil)
      batch_receipt_replay_application = {
        applications: deep_dup(applications)
      }
      batch_receipt_replay_application[:metadata] = deep_dup(metadata) if metadata
      batch_receipt_replay_application
    end

    def structured_edit_provider_batch_execution_receipt_replay_application_envelope(batch_receipt_replay_application)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_application",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_application: deep_dup(batch_receipt_replay_application)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_application_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_application envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_application"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_application envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_application]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_session(receipt_replay_application:, execution_receipt:, metadata: nil)
      replay_session = {
        receipt_replay_application: deep_dup(receipt_replay_application),
        execution_receipt: deep_dup(execution_receipt)
      }
      replay_session[:metadata] = deep_dup(metadata) if metadata
      replay_session
    end

    def structured_edit_provider_execution_receipt_replay_session_envelope(receipt_replay_session)
      {
        kind: "structured_edit_provider_execution_receipt_replay_session",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_session: deep_dup(receipt_replay_session)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_session_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_session envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_session"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_session envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_session]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_session(sessions:, metadata: nil)
      batch_receipt_replay_session = {
        sessions: deep_dup(sessions)
      }
      batch_receipt_replay_session[:metadata] = deep_dup(metadata) if metadata
      batch_receipt_replay_session
    end

    def structured_edit_provider_batch_execution_receipt_replay_session_envelope(batch_receipt_replay_session)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_session",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_session: deep_dup(batch_receipt_replay_session)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_session_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_session envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_session"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_session envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_session]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow(receipt_replay_session:, metadata: nil)
      replay_workflow = {
        receipt_replay_session: deep_dup(receipt_replay_session)
      }
      replay_workflow[:metadata] = deep_dup(metadata) if metadata
      replay_workflow
    end

    def structured_edit_provider_execution_receipt_replay_workflow_envelope(receipt_replay_workflow)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow: deep_dup(receipt_replay_workflow)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow(workflows:, metadata: nil)
      batch_receipt_replay_workflow = {
        workflows: deep_dup(workflows)
      }
      batch_receipt_replay_workflow[:metadata] = deep_dup(metadata) if metadata
      batch_receipt_replay_workflow
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(batch_receipt_replay_workflow)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow: deep_dup(batch_receipt_replay_workflow)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_result(receipt_replay_workflow:, receipt_replay_application:, metadata: nil)
      replay_workflow_result = {
        receipt_replay_workflow: deep_dup(receipt_replay_workflow),
        receipt_replay_application: deep_dup(receipt_replay_application)
      }
      replay_workflow_result[:metadata] = deep_dup(metadata) if metadata
      replay_workflow_result
    end

    def structured_edit_provider_execution_receipt_replay_workflow_result_envelope(receipt_replay_workflow_result)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_result",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_result: deep_dup(receipt_replay_workflow_result)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_result_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_result envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_result"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_result envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_result]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_review_request(receipt_replay_workflow_result:, metadata: nil)
      review_request = {
        receipt_replay_workflow_result: deep_dup(receipt_replay_workflow_result)
      }
      review_request[:metadata] = deep_dup(metadata) if metadata
      review_request
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_request(receipt_replay_workflow_review_request:, metadata: nil)
      apply_request = {
        receipt_replay_workflow_review_request: deep_dup(receipt_replay_workflow_review_request)
      }
      apply_request[:metadata] = deep_dup(metadata) if metadata
      apply_request
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_session(receipt_replay_workflow_apply_request:, receipt_replay_session:, metadata: nil)
      apply_session = {
        receipt_replay_workflow_apply_request: deep_dup(receipt_replay_workflow_apply_request),
        receipt_replay_session: deep_dup(receipt_replay_session)
      }
      apply_session[:metadata] = deep_dup(metadata) if metadata
      apply_session
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_result(receipt_replay_workflow_apply_session:, receipt_replay_workflow_result:, metadata: nil)
      apply_result = {
        receipt_replay_workflow_apply_session: deep_dup(receipt_replay_workflow_apply_session),
        receipt_replay_workflow_result: deep_dup(receipt_replay_workflow_result)
      }
      apply_result[:metadata] = deep_dup(metadata) if metadata
      apply_result
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision(receipt_replay_workflow_apply_result:, decision:, metadata: nil)
      apply_decision = {
        receipt_replay_workflow_apply_result: deep_dup(receipt_replay_workflow_apply_result),
        decision: decision
      }
      apply_decision[:metadata] = deep_dup(metadata) if metadata
      apply_decision
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome(receipt_replay_workflow_apply_decision:, outcome:, metadata: nil)
      apply_decision_outcome = {
        receipt_replay_workflow_apply_decision: deep_dup(receipt_replay_workflow_apply_decision),
        outcome: outcome
      }
      apply_decision_outcome[:metadata] = deep_dup(metadata) if metadata
      apply_decision_outcome
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement(receipt_replay_workflow_apply_decision_outcome:, settlement:, metadata: nil)
      apply_decision_settlement = {
        receipt_replay_workflow_apply_decision_outcome: deep_dup(receipt_replay_workflow_apply_decision_outcome),
        settlement: settlement
      }
      apply_decision_settlement[:metadata] = deep_dup(metadata) if metadata
      apply_decision_settlement
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation(receipt_replay_workflow_apply_decision_settlement:, confirmation:, metadata: nil)
      apply_decision_confirmation = {
        receipt_replay_workflow_apply_decision_settlement: deep_dup(receipt_replay_workflow_apply_decision_settlement),
        confirmation: confirmation
      }
      apply_decision_confirmation[:metadata] = deep_dup(metadata) if metadata
      apply_decision_confirmation
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report(receipt_replay_workflow_apply_decision_confirmation:, closure_report:, metadata: nil)
      apply_decision_closure_report = {
        receipt_replay_workflow_apply_decision_confirmation: deep_dup(receipt_replay_workflow_apply_decision_confirmation),
        closure_report: closure_report
      }
      apply_decision_closure_report[:metadata] = deep_dup(metadata) if metadata
      apply_decision_closure_report
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_audit_record(receipt_replay_workflow_apply_decision_closure_report:, audit_record:, metadata: nil)
      apply_decision_audit_record = {
        receipt_replay_workflow_apply_decision_closure_report: deep_dup(receipt_replay_workflow_apply_decision_closure_report),
        audit_record: audit_record
      }
      apply_decision_audit_record[:metadata] = deep_dup(metadata) if metadata
      apply_decision_audit_record
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(receipt_replay_workflow_apply_decision_settlement)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_decision_settlement: deep_dup(receipt_replay_workflow_apply_decision_settlement)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_decision_settlement]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(receipt_replay_workflow_apply_decision_confirmation)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_decision_confirmation: deep_dup(receipt_replay_workflow_apply_decision_confirmation)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_decision_confirmation]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(receipt_replay_workflow_apply_decision_closure_report)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_decision_closure_report: deep_dup(receipt_replay_workflow_apply_decision_closure_report)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_decision_closure_report]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement(apply_decision_settlements:, metadata: nil)
      batch_apply_decision_settlement = {
        apply_decision_settlements: deep_dup(apply_decision_settlements)
      }
      batch_apply_decision_settlement[:metadata] = deep_dup(metadata) if metadata
      batch_apply_decision_settlement
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(batch_receipt_replay_workflow_apply_decision_settlement)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_decision_settlement: deep_dup(batch_receipt_replay_workflow_apply_decision_settlement)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_decision_settlement]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation(apply_decision_confirmations:, metadata: nil)
      batch_apply_decision_confirmation = {
        apply_decision_confirmations: deep_dup(apply_decision_confirmations)
      }
      batch_apply_decision_confirmation[:metadata] = deep_dup(metadata) if metadata
      batch_apply_decision_confirmation
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report(closure_reports:, metadata: nil)
      batch_apply_decision_closure_report = {
        closure_reports: deep_dup(closure_reports)
      }
      batch_apply_decision_closure_report[:metadata] = deep_dup(metadata) if metadata
      batch_apply_decision_closure_report
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(batch_receipt_replay_workflow_apply_decision_confirmation)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_decision_confirmation: deep_dup(batch_receipt_replay_workflow_apply_decision_confirmation)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_decision_confirmation]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(batch_receipt_replay_workflow_apply_decision_closure_report)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_decision_closure_report: deep_dup(batch_receipt_replay_workflow_apply_decision_closure_report)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_decision_closure_report]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(receipt_replay_workflow_apply_decision_outcome)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_decision_outcome: deep_dup(receipt_replay_workflow_apply_decision_outcome)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_decision_outcome]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(receipt_replay_workflow_apply_decision)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_decision",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_decision: deep_dup(receipt_replay_workflow_apply_decision)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_decision envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_decision"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_decision envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_decision]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(receipt_replay_workflow_apply_result)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_result",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_result: deep_dup(receipt_replay_workflow_apply_result)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_result envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_result"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_result envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_result]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(receipt_replay_workflow_apply_session)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_session",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_session: deep_dup(receipt_replay_workflow_apply_session)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_session envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_session"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_session envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_session]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(receipt_replay_workflow_apply_request)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_apply_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_apply_request: deep_dup(receipt_replay_workflow_apply_request)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_apply_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_apply_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_apply_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_apply_request]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request(apply_requests:, metadata: nil)
      batch_apply_request = {
        apply_requests: deep_dup(apply_requests)
      }
      batch_apply_request[:metadata] = deep_dup(metadata) if metadata
      batch_apply_request
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session(apply_sessions:, metadata: nil)
      batch_apply_session = {
        apply_sessions: deep_dup(apply_sessions)
      }
      batch_apply_session[:metadata] = deep_dup(metadata) if metadata
      batch_apply_session
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result(apply_results:, metadata: nil)
      batch_apply_result = {
        apply_results: deep_dup(apply_results)
      }
      batch_apply_result[:metadata] = deep_dup(metadata) if metadata
      batch_apply_result
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision(apply_decisions:, metadata: nil)
      batch_apply_decision = {
        apply_decisions: deep_dup(apply_decisions)
      }
      batch_apply_decision[:metadata] = deep_dup(metadata) if metadata
      batch_apply_decision
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome(apply_decision_outcomes:, metadata: nil)
      batch_apply_decision_outcome = {
        apply_decision_outcomes: deep_dup(apply_decision_outcomes)
      }
      batch_apply_decision_outcome[:metadata] = deep_dup(metadata) if metadata
      batch_apply_decision_outcome
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(batch_receipt_replay_workflow_apply_request)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_request: deep_dup(batch_receipt_replay_workflow_apply_request)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_request]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(batch_receipt_replay_workflow_apply_session)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_session: deep_dup(batch_receipt_replay_workflow_apply_session)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_session]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(batch_receipt_replay_workflow_apply_result)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_result: deep_dup(batch_receipt_replay_workflow_apply_result)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_result]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(batch_receipt_replay_workflow_apply_decision)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_decision: deep_dup(batch_receipt_replay_workflow_apply_decision)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_decision]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(batch_receipt_replay_workflow_apply_decision_outcome)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_apply_decision_outcome: deep_dup(batch_receipt_replay_workflow_apply_decision_outcome)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_apply_decision_outcome]), nil]
    end

    def structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(receipt_replay_workflow_review_request)
      {
        kind: "structured_edit_provider_execution_receipt_replay_workflow_review_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        receipt_replay_workflow_review_request: deep_dup(receipt_replay_workflow_review_request)
      }
    end

    def import_structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_receipt_replay_workflow_review_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_receipt_replay_workflow_review_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_receipt_replay_workflow_review_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:receipt_replay_workflow_review_request]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_review_request(review_requests:, metadata: nil)
      batch_review_request = {
        review_requests: deep_dup(review_requests)
      }
      batch_review_request[:metadata] = deep_dup(metadata) if metadata
      batch_review_request
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(batch_receipt_replay_workflow_review_request)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_review_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_review_request: deep_dup(batch_receipt_replay_workflow_review_request)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_review_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_review_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_review_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_review_request]), nil]
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_result(receipt_replay_workflow_results:, metadata: nil)
      batch_replay_workflow_result = {
        receipt_replay_workflow_results: deep_dup(receipt_replay_workflow_results)
      }
      batch_replay_workflow_result[:metadata] = deep_dup(metadata) if metadata
      batch_replay_workflow_result
    end

    def structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(batch_receipt_replay_workflow_result)
      {
        kind: "structured_edit_provider_batch_execution_receipt_replay_workflow_result",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_receipt_replay_workflow_result: deep_dup(batch_receipt_replay_workflow_result)
      }
    end

    def import_structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_receipt_replay_workflow_result envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_receipt_replay_workflow_result"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_receipt_replay_workflow_result envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_receipt_replay_workflow_result]), nil]
    end

    def structured_edit_provider_batch_execution_handoff(handoffs:, metadata: nil)
      batch_execution_handoff = {
        handoffs: deep_dup(handoffs)
      }
      batch_execution_handoff[:metadata] = deep_dup(metadata) if metadata
      batch_execution_handoff
    end

    def structured_edit_provider_batch_execution_handoff_envelope(batch_execution_handoff)
      {
        kind: "structured_edit_provider_batch_execution_handoff",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_execution_handoff: deep_dup(batch_execution_handoff)
      }
    end

    def import_structured_edit_provider_batch_execution_handoff_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_handoff envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_handoff"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_handoff envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_execution_handoff]), nil]
    end

    def structured_edit_provider_execution_plan_envelope(execution_plan)
      {
        kind: "structured_edit_provider_execution_plan",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        execution_plan: deep_dup(execution_plan)
      }
    end

    def import_structured_edit_provider_execution_plan_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_plan envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_plan"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_plan envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:execution_plan]), nil]
    end

    def structured_edit_provider_batch_execution_plan(plans:, metadata: nil)
      batch_execution_plan = {
        plans: deep_dup(plans)
      }
      batch_execution_plan[:metadata] = deep_dup(metadata) if metadata
      batch_execution_plan
    end

    def structured_edit_provider_batch_execution_plan_envelope(batch_execution_plan)
      {
        kind: "structured_edit_provider_batch_execution_plan",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_execution_plan: deep_dup(batch_execution_plan)
      }
    end

    def import_structured_edit_provider_batch_execution_plan_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_plan envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_plan"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_plan envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_execution_plan]), nil]
    end

    def structured_edit_provider_execution_application(execution_request:, report:, metadata: nil)
      application = {
        execution_request: deep_dup(execution_request),
        report: deep_dup(report)
      }
      application[:metadata] = deep_dup(metadata) if metadata
      application
    end

    def structured_edit_provider_execution_dispatch(execution_request:, resolved_provider_family:,
      resolved_provider_backend:, executor_label: nil, metadata: nil)
      dispatch = {
        execution_request: deep_dup(execution_request),
        resolved_provider_family: resolved_provider_family.to_s,
        resolved_provider_backend: resolved_provider_backend.to_s
      }
      dispatch[:executor_label] = executor_label.to_s if executor_label
      dispatch[:metadata] = deep_dup(metadata) if metadata
      dispatch
    end

    def structured_edit_provider_execution_dispatch_envelope(provider_execution_dispatch)
      {
        kind: "structured_edit_provider_execution_dispatch",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        provider_execution_dispatch: deep_dup(provider_execution_dispatch)
      }
    end

    def import_structured_edit_provider_execution_dispatch_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_dispatch envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_dispatch"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_dispatch envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:provider_execution_dispatch]), nil]
    end

    def structured_edit_provider_execution_outcome(dispatch:, application:, metadata: nil)
      outcome = {
        dispatch: deep_dup(dispatch),
        application: deep_dup(application)
      }
      outcome[:metadata] = deep_dup(metadata) if metadata
      outcome
    end

    def structured_edit_provider_execution_outcome_envelope(provider_execution_outcome)
      {
        kind: "structured_edit_provider_execution_outcome",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        provider_execution_outcome: deep_dup(provider_execution_outcome)
      }
    end

    def import_structured_edit_provider_execution_outcome_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_outcome envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_outcome"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_outcome envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:provider_execution_outcome]), nil]
    end

    def structured_edit_provider_batch_execution_outcome(outcomes:, metadata: nil)
      batch = {
        outcomes: deep_dup(outcomes)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_outcome_envelope(batch_outcome)
      {
        kind: "structured_edit_provider_batch_execution_outcome",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_outcome: deep_dup(batch_outcome)
      }
    end

    def import_structured_edit_provider_batch_execution_outcome_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_outcome envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_outcome"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_outcome envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_outcome]), nil]
    end

    def structured_edit_provider_execution_provenance(dispatch:, outcome:, diagnostics:, metadata: nil)
      provenance = {
        dispatch: deep_dup(dispatch),
        outcome: deep_dup(outcome),
        diagnostics: deep_dup(diagnostics)
      }
      provenance[:metadata] = deep_dup(metadata) if metadata
      provenance
    end

    def structured_edit_provider_execution_provenance_envelope(provenance)
      {
        kind: "structured_edit_provider_execution_provenance",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        provenance: deep_dup(provenance)
      }
    end

    def import_structured_edit_provider_execution_provenance_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_provenance envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_provenance"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_provenance envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:provenance]), nil]
    end

    def structured_edit_provider_batch_execution_provenance(provenances:, metadata: nil)
      batch = {
        provenances: deep_dup(provenances)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_provenance_envelope(batch_provenance)
      {
        kind: "structured_edit_provider_batch_execution_provenance",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_provenance: deep_dup(batch_provenance)
      }
    end

    def import_structured_edit_provider_batch_execution_provenance_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_provenance envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_provenance"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_provenance envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_provenance]), nil]
    end

    def structured_edit_provider_execution_replay_bundle(execution_request:, provenance:, metadata: nil)
      replay_bundle = {
        execution_request: deep_dup(execution_request),
        provenance: deep_dup(provenance)
      }
      replay_bundle[:metadata] = deep_dup(metadata) if metadata
      replay_bundle
    end

    def structured_edit_provider_execution_replay_bundle_envelope(replay_bundle)
      {
        kind: "structured_edit_provider_execution_replay_bundle",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        replay_bundle: deep_dup(replay_bundle)
      }
    end

    def import_structured_edit_provider_execution_replay_bundle_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_replay_bundle envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_replay_bundle"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_replay_bundle envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:replay_bundle]), nil]
    end

    def structured_edit_provider_batch_execution_replay_bundle(replay_bundles:, metadata: nil)
      batch = {
        replay_bundles: deep_dup(replay_bundles)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_replay_bundle_envelope(batch_replay_bundle)
      {
        kind: "structured_edit_provider_batch_execution_replay_bundle",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_replay_bundle: deep_dup(batch_replay_bundle)
      }
    end

    def import_structured_edit_provider_batch_execution_replay_bundle_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_replay_bundle envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_replay_bundle"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_replay_bundle envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_replay_bundle]), nil]
    end

    def structured_edit_provider_executor_profile(provider_family:, provider_backend:, executor_label:,
      structure_profile:, selection_profile:, match_profile:, operation_profiles:,
      destination_profile:, metadata: nil)
      executor_profile = {
        provider_family: provider_family.to_s,
        provider_backend: provider_backend.to_s,
        executor_label: executor_label.to_s,
        structure_profile: deep_dup(structure_profile),
        selection_profile: deep_dup(selection_profile),
        match_profile: deep_dup(match_profile),
        operation_profiles: deep_dup(operation_profiles),
        destination_profile: deep_dup(destination_profile)
      }
      executor_profile[:metadata] = deep_dup(metadata) if metadata
      executor_profile
    end

    def structured_edit_provider_executor_profile_envelope(executor_profile)
      {
        kind: "structured_edit_provider_executor_profile",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        executor_profile: deep_dup(executor_profile)
      }
    end

    def import_structured_edit_provider_executor_profile_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_executor_profile envelope kind." }] unless envelope[:kind] == "structured_edit_provider_executor_profile"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_executor_profile envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:executor_profile]), nil]
    end

    def structured_edit_provider_executor_registry(executor_profiles:, metadata: nil)
      executor_registry = {
        executor_profiles: deep_dup(executor_profiles)
      }
      executor_registry[:metadata] = deep_dup(metadata) if metadata
      executor_registry
    end

    def structured_edit_provider_executor_selection_policy(provider_family:, selection_mode:,
      allow_registry_fallback:, provider_backend: nil, executor_label: nil, metadata: nil)
      selection_policy = {
        provider_family: provider_family.to_s,
        selection_mode: selection_mode.to_s,
        allow_registry_fallback: allow_registry_fallback ? true : false
      }
      selection_policy[:provider_backend] = provider_backend.to_s if provider_backend
      selection_policy[:executor_label] = executor_label.to_s if executor_label
      selection_policy[:metadata] = deep_dup(metadata) if metadata
      selection_policy
    end

    def structured_edit_provider_executor_resolution(executor_registry:, selection_policy:,
      selected_executor_profile:, metadata: nil)
      executor_resolution = {
        executor_registry: deep_dup(executor_registry),
        selection_policy: deep_dup(selection_policy),
        selected_executor_profile: deep_dup(selected_executor_profile)
      }
      executor_resolution[:metadata] = deep_dup(metadata) if metadata
      executor_resolution
    end

    def structured_edit_provider_executor_selection_policy_envelope(selection_policy)
      {
        kind: "structured_edit_provider_executor_selection_policy",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        selection_policy: deep_dup(selection_policy)
      }
    end

    def import_structured_edit_provider_executor_selection_policy_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_executor_selection_policy envelope kind." }] unless envelope[:kind] == "structured_edit_provider_executor_selection_policy"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_executor_selection_policy envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:selection_policy]), nil]
    end

    def structured_edit_provider_executor_resolution_envelope(executor_resolution)
      {
        kind: "structured_edit_provider_executor_resolution",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        executor_resolution: deep_dup(executor_resolution)
      }
    end

    def import_structured_edit_provider_executor_resolution_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_executor_resolution envelope kind." }] unless envelope[:kind] == "structured_edit_provider_executor_resolution"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_executor_resolution envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:executor_resolution]), nil]
    end

    def structured_edit_provider_executor_registry_envelope(executor_registry)
      {
        kind: "structured_edit_provider_executor_registry",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        executor_registry: deep_dup(executor_registry)
      }
    end

    def import_structured_edit_provider_executor_registry_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_executor_registry envelope kind." }] unless envelope[:kind] == "structured_edit_provider_executor_registry"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_executor_registry envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:executor_registry]), nil]
    end

    def structured_edit_provider_execution_application_envelope(provider_execution_application)
      {
        kind: "structured_edit_provider_execution_application",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        provider_execution_application: deep_dup(provider_execution_application)
      }
    end

    def import_structured_edit_provider_execution_application_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_execution_application envelope kind." }] unless envelope[:kind] == "structured_edit_provider_execution_application"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_execution_application envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:provider_execution_application]), nil]
    end

    def structured_edit_execution_report_envelope(report)
      {
        kind: "structured_edit_execution_report",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        report: deep_dup(report)
      }
    end

    def import_structured_edit_execution_report_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_execution_report envelope kind." }] unless envelope[:kind] == "structured_edit_execution_report"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_execution_report envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:report]), nil]
    end

    def structured_edit_batch_request(requests:, metadata: nil)
      batch = {
        requests: deep_dup(requests)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_request(requests:, metadata: nil)
      batch = {
        requests: deep_dup(requests)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_request_envelope(batch_execution_request)
      {
        kind: "structured_edit_provider_batch_execution_request",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_execution_request: deep_dup(batch_execution_request)
      }
    end

    def import_structured_edit_provider_batch_execution_request_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_request envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_request"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_request envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_execution_request]), nil]
    end

    def structured_edit_provider_batch_execution_dispatch(dispatches:, metadata: nil)
      batch = {
        dispatches: deep_dup(dispatches)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_dispatch_envelope(batch_dispatch)
      {
        kind: "structured_edit_provider_batch_execution_dispatch",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_dispatch: deep_dup(batch_dispatch)
      }
    end

    def import_structured_edit_provider_batch_execution_dispatch_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_dispatch envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_dispatch"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_dispatch envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_dispatch]), nil]
    end

    def structured_edit_provider_batch_execution_report(applications:, diagnostics:, metadata: nil)
      batch = {
        applications: deep_dup(applications),
        diagnostics: deep_dup(diagnostics)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_provider_batch_execution_report_envelope(batch_report)
      {
        kind: "structured_edit_provider_batch_execution_report",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_report: deep_dup(batch_report)
      }
    end

    def import_structured_edit_provider_batch_execution_report_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_provider_batch_execution_report envelope kind." }] unless envelope[:kind] == "structured_edit_provider_batch_execution_report"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_provider_batch_execution_report envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_report]), nil]
    end

    def structured_edit_batch_report(reports:, diagnostics:, metadata: nil)
      batch = {
        reports: deep_dup(reports),
        diagnostics: deep_dup(diagnostics)
      }
      batch[:metadata] = deep_dup(metadata) if metadata
      batch
    end

    def structured_edit_batch_report_envelope(batch_report)
      {
        kind: "structured_edit_batch_report",
        version: STRUCTURED_EDIT_TRANSPORT_VERSION,
        batch_report: deep_dup(batch_report)
      }
    end

    def import_structured_edit_batch_report_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected structured_edit_batch_report envelope kind." }] unless envelope[:kind] == "structured_edit_batch_report"
      return [nil, { category: "unsupported_version", message: "unsupported structured_edit_batch_report envelope version #{envelope[:version]}." }] unless envelope[:version] == STRUCTURED_EDIT_TRANSPORT_VERSION

      [deep_dup(envelope[:batch_report]), nil]
    end

    def projected_child_review_case(case_id:, parent_operation_id:, child_operation_id:, surface_path:,
      delegated_case_id:, delegated_apply_group:, delegated_runtime_surface_path:)
      {
        case_id: case_id,
        parent_operation_id: parent_operation_id,
        child_operation_id: child_operation_id,
        surface_path: surface_path,
        delegated_case_id: delegated_case_id,
        delegated_apply_group: delegated_apply_group,
        delegated_runtime_surface_path: delegated_runtime_surface_path
      }
    end

    def group_projected_child_review_cases(cases)
      groups = []

      cases.each do |entry|
        existing = groups.find { |group| group[:delegated_apply_group] == entry[:delegated_apply_group] }
        if existing
          existing[:case_ids] << entry[:case_id]
          existing[:delegated_case_ids] << entry[:delegated_case_id]
          next
        end

        groups << {
          delegated_apply_group: entry[:delegated_apply_group],
          parent_operation_id: entry[:parent_operation_id],
          child_operation_id: entry[:child_operation_id],
          delegated_runtime_surface_path: entry[:delegated_runtime_surface_path],
          case_ids: [entry[:case_id]],
          delegated_case_ids: [entry[:delegated_case_id]]
        }
      end

      groups
    end

    def summarize_projected_child_review_group_progress(groups, resolved_case_ids)
      groups.map do |group|
        resolved = group[:case_ids].select { |case_id| resolved_case_ids.include?(case_id) }
        pending = group[:case_ids].reject { |case_id| resolved_case_ids.include?(case_id) }

        {
          delegated_apply_group: group[:delegated_apply_group],
          parent_operation_id: group[:parent_operation_id],
          child_operation_id: group[:child_operation_id],
          delegated_runtime_surface_path: group[:delegated_runtime_surface_path],
          resolved_case_ids: resolved,
          pending_case_ids: pending,
          complete: pending.empty?
        }
      end
    end

    def select_projected_child_review_groups_ready_for_apply(groups, resolved_case_ids)
      groups.select do |group|
        group[:case_ids].all? { |case_id| resolved_case_ids.include?(case_id) }
      end
    end

    def review_request_id_for_projected_child_group(group)
      "projected_child_group:#{group[:delegated_apply_group]}"
    end

    def projected_child_group_review_request(group, family)
      {
        id: review_request_id_for_projected_child_group(group),
        kind: "delegated_child_group",
        family: family,
        message: "delegated child group #{group[:delegated_apply_group]} is ready to apply for #{family}.",
        blocking: true,
        delegated_group: deep_dup(group),
        action_offers: [
          { action: "apply_delegated_child_group", requires_context: false }
        ],
        default_action: "apply_delegated_child_group"
      }
    end

    def select_projected_child_review_groups_accepted_for_apply(groups, _family, decisions)
      accepted_request_ids = decisions
        .select { |decision| decision[:action] == "apply_delegated_child_group" }
        .map { |decision| decision[:request_id] }

      groups.select do |group|
        accepted_request_ids.include?(review_request_id_for_projected_child_group(group))
      end
    end

    def review_projected_child_groups(groups, family, decisions)
      request_ids = groups.map { |group| review_request_id_for_projected_child_group(group) }
      applied_decisions = []
      diagnostics = []

      decisions.each do |decision|
        next unless decision[:action] == "apply_delegated_child_group"

        if request_ids.include?(decision[:request_id])
          applied_decisions << deep_dup(decision)
        else
          diagnostics << diagnostic(
            "error",
            "replay_rejected",
            "review decision #{decision[:request_id]} does not match any current delegated child review request.",
            review: {
              request_id: decision[:request_id],
              action: decision[:action],
              reason: "request_not_found"
            }
          )
        end
      end

      accepted_groups = select_projected_child_review_groups_accepted_for_apply(
        groups,
        family,
        applied_decisions
      )
      accepted_request_ids = accepted_groups.map do |group|
        review_request_id_for_projected_child_group(group)
      end
      requests = groups.reject do |group|
        accepted_request_ids.include?(review_request_id_for_projected_child_group(group))
      end.map do |group|
        projected_child_group_review_request(group, family)
      end

      {
        requests: requests,
        accepted_groups: accepted_groups,
        applied_decisions: applied_decisions,
        diagnostics: diagnostics
      }
    end

    def delegated_child_apply_plan(state, family)
      entries = state.fetch(:accepted_groups, []).filter_map do |group|
        request_id = review_request_id_for_projected_child_group(group)
        decision = state.fetch(:applied_decisions, []).find do |candidate|
          candidate[:request_id] == request_id
        end
        next unless decision

        {
          request_id: request_id,
          family: family,
          delegated_group: deep_dup(group),
          decision: deep_dup(decision)
        }
      end

      { entries: entries }
    end

    def resolve_delegated_child_outputs(operations, nested_outputs, default_family:, request_id_prefix:)
      operations_by_surface_address = operations.each_with_object({}) do |operation, memo|
        memo[operation.dig(:surface, :address)] = operation
      end

      nested_outputs.each do |entry|
        next if operations_by_surface_address.key?(entry[:surface_address])

        return {
          ok: false,
          diagnostics: [
            diagnostic(
              "error",
              "configuration_error",
              "missing delegated child surface #{entry[:surface_address]}."
            )
          ]
        }
      end

      {
        ok: true,
        diagnostics: [],
        apply_plan: {
          entries: nested_outputs.each_with_index.map do |entry, index|
            operation = operations_by_surface_address.fetch(entry[:surface_address])
            request_id = "#{request_id_prefix}:#{index}"
            {
              request_id: request_id,
              family: operation.dig(:surface, :metadata, :family) || default_family,
              delegated_group: {
                delegated_apply_group: request_id,
                parent_operation_id: operation[:parent_operation_id],
                child_operation_id: operation[:operation_id],
                delegated_runtime_surface_path: entry[:surface_address],
                case_ids: [],
                delegated_case_ids: []
              },
              decision: {
                request_id: request_id,
                action: "apply_delegated_child_group"
              }
            }
          end
        },
        applied_children: nested_outputs.map do |entry|
          operation = operations_by_surface_address.fetch(entry[:surface_address])
          {
            operation_id: operation[:operation_id],
            output: entry[:output]
          }
        end
      }
    end

    def execute_nested_merge(nested_outputs, default_family:, request_id_prefix:, merge_parent:, discover_operations:, apply_resolved_outputs:)
      merged = merge_parent.call
      return merged unless merged[:ok] && merged.key?(:output)

      discovery = discover_operations.call(merged[:output])
      return { ok: false, diagnostics: discovery[:diagnostics] || [], policies: [] } unless discovery[:ok] && discovery[:operations]

      resolution = resolve_delegated_child_outputs(
        discovery[:operations],
        nested_outputs,
        default_family: default_family,
        request_id_prefix: request_id_prefix
      )
      return resolution.merge(policies: []) unless resolution[:ok]

      apply_resolved_outputs.call(
        merged[:output],
        discovery[:operations],
        resolution[:apply_plan],
        resolution[:applied_children]
      )
    end

    def execute_delegated_child_apply_plan(apply_plan, applied_children, merge_parent:, discover_operations:, apply_resolved_outputs:)
      merged = merge_parent.call
      return merged unless merged[:ok] && merged.key?(:output)

      discovery = discover_operations.call(merged[:output])
      return { ok: false, diagnostics: discovery[:diagnostics] || [], policies: [] } unless discovery[:ok] && discovery[:operations]

      apply_resolved_outputs.call(
        merged[:output],
        discovery[:operations],
        apply_plan,
        applied_children
      )
    end

    def execute_reviewed_nested_merge(review_state, family, applied_children, merge_parent:, discover_operations:, apply_resolved_outputs:)
      execute_delegated_child_apply_plan(
        delegated_child_apply_plan(review_state, family),
        applied_children,
        merge_parent: merge_parent,
        discover_operations: discover_operations,
        apply_resolved_outputs: apply_resolved_outputs
      )
    end

    def reviewed_nested_execution(family, review_state, applied_children)
      {
        family: family,
        review_state: deep_dup(review_state),
        applied_children: deep_dup(applied_children)
      }
    end

    def execute_reviewed_nested_execution(execution, merge_parent:, discover_operations:, apply_resolved_outputs:)
      execute_reviewed_nested_merge(
        execution[:review_state],
        execution[:family],
        execution[:applied_children],
        merge_parent: merge_parent,
        discover_operations: discover_operations,
        apply_resolved_outputs: apply_resolved_outputs
      )
    end

    def execute_reviewed_nested_executions(executions, &callbacks_for_execution)
      executions.each_with_index.map do |execution, index|
        callbacks = callbacks_for_execution.call(execution, index)
        {
          execution: deep_dup(execution),
          result: execute_reviewed_nested_execution(
            execution,
            merge_parent: callbacks.fetch(:merge_parent),
            discover_operations: callbacks.fetch(:discover_operations),
            apply_resolved_outputs: callbacks.fetch(:apply_resolved_outputs)
          )
        }
      end
    end

    def execute_review_replay_bundle_reviewed_nested_executions(bundle, &callbacks_for_execution)
      execute_reviewed_nested_executions(bundle.fetch(:reviewed_nested_executions, []), &callbacks_for_execution)
    end

    def execute_review_replay_bundle_envelope_reviewed_nested_executions(envelope, &callbacks_for_execution)
      bundle, import_error = import_review_replay_bundle_envelope(envelope)
      return { diagnostics: [diagnostic("error", import_error[:category], import_error[:message])], results: [] } if import_error

      {
        diagnostics: [],
        results: execute_review_replay_bundle_reviewed_nested_executions(bundle, &callbacks_for_execution)
      }
    end

    def execute_review_state_reviewed_nested_executions(state, &callbacks_for_execution)
      execute_reviewed_nested_executions(state.fetch(:reviewed_nested_executions, []), &callbacks_for_execution)
    end

    def execute_review_state_envelope_reviewed_nested_executions(envelope, &callbacks_for_execution)
      state, import_error = import_conformance_manifest_review_state_envelope(envelope)
      return { diagnostics: [diagnostic("error", import_error[:category], import_error[:message])], results: [] } if import_error

      {
        diagnostics: [],
        results: execute_review_state_reviewed_nested_executions(state, &callbacks_for_execution)
      }
    end

    def review_and_execute_conformance_manifest_with_replay_bundle_envelope(
      manifest,
      options,
      replay_bundle_envelope,
      execute:,
      reviewed_nested_execution:
    )
      state = review_conformance_manifest_with_replay_bundle_envelope(
        manifest,
        options,
        replay_bundle_envelope,
        &execute
      )

      {
        state: state,
        results: execute_review_state_reviewed_nested_executions(state, &reviewed_nested_execution)
      }
    end

    def conformance_manifest_replay_context(manifest, options)
      seen = {}
      families = conformance_suite_selectors(manifest).filter_map do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)
        next if seen[family]

        seen[family] = true
        family
      end

      {
        surface: "conformance_manifest",
        families: families,
        require_explicit_contexts: options.fetch(:require_explicit_contexts, false)
      }
    end

    def review_replay_context_compatible(current, candidate)
      return false unless candidate

      current[:surface] == candidate[:surface] &&
        current[:require_explicit_contexts] == candidate[:require_explicit_contexts] &&
        current[:families] == candidate[:families]
    end

    def conformance_manifest_review_request_ids(manifest, options)
      return [] unless options.fetch(:require_explicit_contexts, false)

      seen = {}
      conformance_suite_selectors(manifest).filter_map do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)
        next if seen[family]

        seen[family] = true
        contexts = options.fetch(:contexts, {})
        family_profiles = options.fetch(:family_profiles, {})
        next if contexts.key?(family.to_sym) || contexts.key?(family)
        next unless family_profiles.key?(family.to_sym) || family_profiles.key?(family)

        review_request_id_for_family_context(family)
      end
    end

    def review_replay_bundle_inputs(options)
      if options[:review_replay_bundle]
        bundle = options[:review_replay_bundle]
        [bundle[:replay_context], bundle[:decisions] || [], bundle[:reviewed_nested_executions] || []]
      else
        [options[:review_replay_context], options[:review_decisions] || [], []]
      end
    end

    def conformance_manifest_review_state_envelope(state)
      {
        kind: "conformance_manifest_review_state",
        version: REVIEW_TRANSPORT_VERSION,
        state: deep_dup(state)
      }
    end

    def review_replay_bundle_envelope(bundle)
      {
        kind: "review_replay_bundle",
        version: REVIEW_TRANSPORT_VERSION,
        replay_bundle: deep_dup(bundle)
      }
    end

    def reviewed_nested_execution_envelope(execution)
      {
        kind: "reviewed_nested_execution",
        version: REVIEW_TRANSPORT_VERSION,
        execution: deep_dup(execution)
      }
    end

    def import_conformance_manifest_review_state_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected conformance_manifest_review_state envelope kind." }] unless envelope[:kind] == "conformance_manifest_review_state"
      return [nil, { category: "unsupported_version", message: "unsupported conformance_manifest_review_state envelope version #{envelope[:version]}." }] unless envelope[:version] == REVIEW_TRANSPORT_VERSION

      [deep_dup(envelope[:state]), nil]
    end

    def import_review_replay_bundle_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected review_replay_bundle envelope kind." }] unless envelope[:kind] == "review_replay_bundle"
      return [nil, { category: "unsupported_version", message: "unsupported review_replay_bundle envelope version #{envelope[:version]}." }] unless envelope[:version] == REVIEW_TRANSPORT_VERSION

      [deep_dup(envelope[:replay_bundle]), nil]
    end

    def import_reviewed_nested_execution_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected reviewed_nested_execution envelope kind." }] unless envelope[:kind] == "reviewed_nested_execution"
      return [nil, { category: "unsupported_version", message: "unsupported reviewed_nested_execution envelope version #{envelope[:version]}." }] unless envelope[:version] == REVIEW_TRANSPORT_VERSION

      [deep_dup(envelope[:execution]), nil]
    end

    def resolve_conformance_family_context(family, options)
      contexts = options.fetch(:contexts, {})
      key = family.to_sym
      return [deep_dup(contexts[key] || contexts[family.to_s]), []] if contexts.key?(key) || contexts.key?(family.to_s)

      if options.fetch(:require_explicit_contexts, false)
        return [nil, [diagnostic("error", "configuration_error", "missing explicit family context for #{family}.")]]
      end

      family_profiles = options.fetch(:family_profiles, {})
      if family_profiles.key?(key) || family_profiles.key?(family.to_s)
        context = default_conformance_family_context(family_profiles[key] || family_profiles[family.to_s])
        diagnostics = [diagnostic("warning", "assumed_default", "using default family context for #{family}.")]
        return [context, diagnostics]
      end

      [nil, [diagnostic("error", "configuration_error", "missing family context for #{family} and no default family profile is available.")]]
    end

    def review_conformance_family_context(family, options)
      contexts = options.fetch(:contexts, {})
      key = family.to_sym
      return [deep_dup(contexts[key] || contexts[family.to_s]), [], [], []] if contexts.key?(key) || contexts.key?(family.to_s)

      unless options.fetch(:require_explicit_contexts, false)
        context, diagnostics = resolve_conformance_family_context(
          family,
          contexts: options.fetch(:contexts, {}),
          family_profiles: options.fetch(:family_profiles, {}),
          require_explicit_contexts: false
        )
        return [context, diagnostics, [], []]
      end

      family_profiles = options.fetch(:family_profiles, {})
      family_profile = family_profiles[key] || family_profiles[family.to_s]
      unless family_profile
        return [nil, [diagnostic("error", "configuration_error", "missing family context for #{family} and no default family profile is available.")], [], []]
      end

      context, applied_decision, assumed_default, decision_diagnostics = review_decision_for_family_context(family, options)
      if applied_decision
        diagnostics = assumed_default ? [diagnostic("warning", "assumed_default", "using default family context for #{family}.")] : []
        return [context, diagnostics, [], [applied_decision]]
      end

      request = family_context_review_request(family, family_profile)
      return [nil, decision_diagnostics, [request], []] unless decision_diagnostics.empty?

      [
        nil,
        [diagnostic("error", "configuration_error", "missing explicit family context for #{family}.")],
        [request],
        []
      ]
    end

    def summarize_conformance_results(results)
      results.each_with_object({ total: 0, passed: 0, failed: 0, skipped: 0 }) do |result, summary|
        summary[:total] += 1
        case result[:outcome]
        when "passed" then summary[:passed] += 1
        when "failed" then summary[:failed] += 1
        when "skipped" then summary[:skipped] += 1
        end
      end
    end

    def select_conformance_case(ref, requirements, family_profile, feature_profile = nil)
      messages = []

      if requirements[:backend]
        if feature_profile.nil?
          messages << "case requires backend #{requirements[:backend]} but no backend feature profile is available for family #{family_profile[:family]}."
        elsif feature_profile[:backend] != requirements[:backend]
          messages << "case requires backend #{requirements[:backend]} but backend #{feature_profile[:backend]} is active for family #{family_profile[:family]}."
        end
      end

      if requirements[:dialect]
        if !family_profile.fetch(:supported_dialects, []).include?(requirements[:dialect])
          messages << "family #{family_profile[:family]} does not support dialect #{requirements[:dialect]}."
        elsif feature_profile && !feature_profile[:supports_dialects] && !default_dialect?(family_profile, requirements[:dialect])
          messages << "backend #{feature_profile[:backend]} does not support dialect #{requirements[:dialect]} for family #{family_profile[:family]}."
        end
      end

      requirements.fetch(:policies, []).each do |policy|
        unless includes_policy?(family_profile.fetch(:supported_policies, []), policy)
          messages << "family #{family_profile[:family]} does not support policy #{policy[:name]}."
          next
        end

        if feature_profile && !includes_policy?(feature_profile.fetch(:supported_policies, []), policy)
          messages << "backend #{feature_profile[:backend]} does not support policy #{policy[:name]}."
        end
      end

      {
        ref: deep_dup(ref),
        status: messages.empty? ? "selected" : "skipped",
        messages: messages
      }
    end

    def run_conformance_case(run, &execute)
      selection = select_conformance_case(run[:ref], run[:requirements], run[:family_profile], run[:feature_profile])
      return { ref: deep_dup(run[:ref]), outcome: "skipped", messages: selection[:messages] } if selection[:status] == "skipped"

      execution = execute.call(run)
      {
        ref: deep_dup(run[:ref]),
        outcome: execution[:outcome],
        messages: deep_dup(execution[:messages] || [])
      }
    end

    def run_conformance_suite(runs, &execute)
      runs.map { |run| run_conformance_case(run, &execute) }
    end

    def run_planned_conformance_suite(plan, &execute)
      plan[:entries].map { |entry| run_conformance_case(entry[:run], &execute) }
    end

    def run_named_conformance_suite(manifest, selector, family_profile, feature_profile = nil, &execute)
      plan = plan_named_conformance_suite(manifest, selector, family_profile, feature_profile)
      plan && run_planned_conformance_suite(plan, &execute)
    end

    def run_named_conformance_suite_entry(manifest, selector, family_profile, feature_profile = nil, &execute)
      results = run_named_conformance_suite(manifest, selector, family_profile, feature_profile, &execute)
      definition = conformance_suite_definition(manifest, selector)
      results && definition && { suite: definition, results: results }
    end

    def run_planned_named_conformance_suites(entries, &execute)
      entries.map { |entry| { suite: entry[:suite], results: run_planned_conformance_suite(entry[:plan], &execute) } }
    end

    def report_planned_conformance_suite(plan, &execute)
      report_conformance_suite(run_planned_conformance_suite(plan, &execute))
    end

    def report_named_conformance_suite(manifest, selector, family_profile, feature_profile = nil, &execute)
      plan = plan_named_conformance_suite(manifest, selector, family_profile, feature_profile)
      plan && report_planned_conformance_suite(plan, &execute)
    end

    def report_named_conformance_suite_entry(manifest, selector, family_profile, feature_profile = nil, &execute)
      report = report_named_conformance_suite(manifest, selector, family_profile, feature_profile, &execute)
      definition = conformance_suite_definition(manifest, selector)
      report && definition && { suite: definition, report: report }
    end

    def report_planned_named_conformance_suites(entries, &execute)
      entries.map { |entry| { suite: entry[:suite], report: report_planned_conformance_suite(entry[:plan], &execute) } }
    end

    def summarize_named_conformance_suite_reports(entries)
      entries.each_with_object({ total: 0, passed: 0, failed: 0, skipped: 0 }) do |entry, summary|
        report_summary = entry.dig(:report, :summary) || {}
        summary[:total] += report_summary.fetch(:total, 0)
        summary[:passed] += report_summary.fetch(:passed, 0)
        summary[:failed] += report_summary.fetch(:failed, 0)
        summary[:skipped] += report_summary.fetch(:skipped, 0)
      end
    end

    def report_named_conformance_suite_envelope(entries)
      { entries: deep_dup(entries), summary: summarize_named_conformance_suite_reports(entries) }
    end

    def report_named_conformance_suite_manifest(manifest, contexts, &execute)
      report_named_conformance_suite_envelope(
        report_planned_named_conformance_suites(
          plan_named_conformance_suites(manifest, contexts),
          &execute
        )
      )
    end

    def report_conformance_manifest(manifest, options, &execute)
      planned = plan_named_conformance_suites_with_diagnostics(manifest, options)
      {
        report: report_named_conformance_suite_envelope(report_planned_named_conformance_suites(planned[:entries], &execute)),
        diagnostics: planned[:diagnostics]
      }
    end

    def review_conformance_manifest(manifest, options, &execute)
      replay_context = conformance_manifest_replay_context(manifest, options)
      entries = []
      diagnostics = []
      requests = []
      applied_decisions = []
      effective_options = deep_dup(options)
      replay_input_context, replay_input_decisions, reviewed_nested_executions = review_replay_bundle_inputs(options)

      if replay_input_decisions.any?
        if replay_input_context.nil?
          diagnostics << diagnostic("error", "replay_rejected", "review decisions were provided without replay context.")
          effective_options[:review_replay_bundle] = nil
          effective_options[:review_replay_context] = nil
          effective_options[:review_decisions] = []
          reviewed_nested_executions = []
        elsif !review_replay_context_compatible(replay_context, replay_input_context)
          diagnostics << diagnostic("error", "replay_rejected", "review replay context does not match the current conformance manifest state.")
          effective_options[:review_replay_bundle] = nil
          effective_options[:review_replay_context] = nil
          effective_options[:review_decisions] = []
          reviewed_nested_executions = []
        else
          allowed_request_ids = conformance_manifest_review_request_ids(manifest, options).to_h { |request_id| [request_id, true] }
          accepted_decisions = []

          replay_input_decisions.each do |decision|
            if allowed_request_ids[decision[:request_id]]
              accepted_decisions << deep_dup(decision)
            else
              diagnostics << diagnostic(
                "error",
                "replay_rejected",
                "review decision #{decision[:request_id]} does not match any current review request.",
                review: {
                  request_id: decision[:request_id],
                  action: decision[:action],
                  reason: "request_not_found"
                }
              )
            end
          end

          effective_options[:review_replay_bundle] = nil
          effective_options[:review_replay_context] = deep_dup(replay_input_context)
          effective_options[:review_decisions] = accepted_decisions
        end
      end

      resolved_contexts = {}

      conformance_suite_selectors(manifest).each do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)

        context =
          if resolved_contexts.key?(family)
            resolved_contexts[family]
          else
            resolved_context, resolved_diagnostics, resolved_requests, resolved_applied_decisions = review_conformance_family_context(family, effective_options)
            diagnostics.concat(resolved_diagnostics)
            requests.concat(resolved_requests)
            applied_decisions.concat(resolved_applied_decisions)
            resolved_contexts[family] = resolved_context
            resolved_context
          end
        next unless context

        entry = plan_named_conformance_suite_entry(manifest, selector, context)
        next unless entry

        if entry[:plan][:missing_roles].any?
          diagnostics << diagnostic("error", "configuration_error", "suite #{conformance_suite_descriptor_string(entry[:suite])} declares missing roles: #{join_comma(entry[:plan][:missing_roles])}.")
          next
        end

        entries << entry
      end

      {
        report: report_named_conformance_suite_envelope(report_planned_named_conformance_suites(entries, &execute)),
        diagnostics: diagnostics,
        requests: requests,
        applied_decisions: applied_decisions,
        host_hints: conformance_review_host_hints(options),
        replay_context: replay_context
      }.tap do |state|
        state[:reviewed_nested_executions] = deep_dup(reviewed_nested_executions) unless reviewed_nested_executions.empty?
      end
    end

    def review_conformance_manifest_with_replay_bundle_envelope(manifest, options, replay_bundle_envelope, &execute)
      replay_bundle, import_error = import_review_replay_bundle_envelope(replay_bundle_envelope)
      if import_error.nil?
        return review_conformance_manifest(
          manifest,
          deep_dup(options).merge(review_replay_bundle: replay_bundle),
          &execute
        )
      end

      state = review_conformance_manifest(
        manifest,
        deep_dup(options).merge(review_replay_bundle: nil),
        &execute
      )
      state[:diagnostics] << diagnostic("error", import_error[:category], import_error[:message])
      state
    end

    def report_conformance_suite(results)
      { results: deep_dup(results), summary: summarize_conformance_results(results) }
    end

    def plan_conformance_suite(manifest, family, roles, family_profile, feature_profile = nil)
      entries = []
      missing_roles = []

      roles.each do |role|
        entry = conformance_family_entries(manifest, family).find { |candidate| candidate[:role] == role }
        unless entry
          missing_roles << role
          next
        end

        ref = { family: family, role: role, case: role }
        run = {
          ref: ref,
          requirements: deep_dup(entry[:requirements] || {}),
          family_profile: deep_dup(family_profile)
        }
        run[:feature_profile] = deep_dup(feature_profile) if feature_profile
        entries << {
          ref: ref,
          path: deep_dup(entry[:path]),
          run: run
        }
      end

      { family: family, entries: entries, missing_roles: missing_roles }
    end

    def plan_named_conformance_suite(manifest, selector, family_profile, feature_profile = nil)
      definition = conformance_suite_definition(manifest, selector)
      return nil unless definition

      plan_conformance_suite(manifest, definition.dig(:subject, :grammar), definition[:roles], family_profile, feature_profile)
    end

    def plan_named_conformance_suite_entry(manifest, selector, context)
      plan = plan_named_conformance_suite(manifest, selector, context[:family_profile], context[:feature_profile])
      definition = conformance_suite_definition(manifest, selector)
      plan && definition && { suite: definition, plan: plan }
    end

    def plan_named_conformance_suites(manifest, contexts)
      conformance_suite_selectors(manifest).filter_map do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)
        family_key = family.to_sym
        next unless contexts.key?(family_key) || contexts.key?(family)

        plan_named_conformance_suite_entry(manifest, selector, contexts[family_key] || contexts[family])
      end
    end

    def plan_named_conformance_suites_with_diagnostics(manifest, options)
      entries = []
      diagnostics = []
      resolved_contexts = {}

      conformance_suite_selectors(manifest).each do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)

        context =
          if resolved_contexts.key?(family)
            resolved_contexts[family]
          else
            resolved_context, resolved_diagnostics = resolve_conformance_family_context(family, options)
            diagnostics.concat(resolved_diagnostics)
            resolved_contexts[family] = resolved_context
            resolved_context
          end
        next unless context

        entry = plan_named_conformance_suite_entry(manifest, selector, context)
        next unless entry

        if entry[:plan][:missing_roles].any?
          diagnostics << diagnostic("error", "configuration_error", "suite #{conformance_suite_descriptor_string(entry[:suite])} declares missing roles: #{join_comma(entry[:plan][:missing_roles])}.")
          next
        end

        entries << entry
      end

      { entries: entries, diagnostics: diagnostics }
    end

    def normalize_value(value)
      deep_symbolize(value)
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end

    def template_target_classification(path, file_type, family, dialect)
      {
        destination_path: path,
        file_type: file_type,
        family: family,
        dialect: dialect
      }
    end

    def deep_symbolize(value)
      case value
      when Array
        value.map { |item| deep_symbolize(item) }
      when Hash
        value.each_with_object({}) do |(key, item), memo|
          memo[key.to_sym] = deep_symbolize(item)
        end
      else
        value
      end
    end

    def json_ready(value)
      case value
      when Array
        value.map { |item| json_ready(item) }
      when Hash
        value.each_with_object({}) do |(key, item), memo|
          memo[key.to_s] = json_ready(item)
        end
      else
        value
      end
    end

    def includes_policy?(supported_policies, policy)
      supported_policies.any? { |candidate| candidate == policy }
    end
    private_class_method :includes_policy?

    def default_dialect?(family_profile, dialect)
      dialect == family_profile[:family]
    end
    private_class_method :default_dialect?

    private_class_method :record_template_apply_output

    def review_decision_for_family_context(family, options)
      request_id = review_request_id_for_family_context(family)
      family_profiles = options.fetch(:family_profiles, {})
      family_profile = family_profiles[family.to_sym] || family_profiles[family]

      (options[:review_decisions] || []).each do |decision|
        next unless decision[:request_id] == request_id

        if decision[:action] == "accept_default_context" && family_profile
          return [default_conformance_family_context(family_profile), deep_dup(decision), true, []]
        end

        if decision[:action] == "provide_explicit_context" && decision[:context].nil?
          diagnostics = [
            diagnostic(
              "error",
              "configuration_error",
              "review decision #{request_id} requires explicit context payload.",
              review: {
                request_id: request_id,
                action: "provide_explicit_context",
                reason: "missing_required_payload",
                payload_kind: "conformance_family_context"
              }
            )
          ]
          return [nil, nil, false, diagnostics]
        end

        if decision[:action] == "provide_explicit_context" && decision[:context]
          provided_family = decision.dig(:context, :family_profile, :family)
          if provided_family != family
            diagnostics = [
              diagnostic(
                "error",
                "configuration_error",
                "review decision #{request_id} provided context for #{provided_family}, expected #{family}.",
                review: {
                  request_id: request_id,
                  action: "provide_explicit_context",
                  reason: "family_mismatch",
                  expected_family: family,
                  provided_family: provided_family
                }
              )
            ]
            return [nil, nil, false, diagnostics]
          end

          return [deep_dup(decision[:context]), deep_dup(decision), false, []]
        end
      end

      [nil, nil, false, []]
    end
    private_class_method :review_decision_for_family_context

    def family_context_review_request(family, family_profile)
      {
        id: review_request_id_for_family_context(family),
        kind: "family_context",
        family: family,
        message: "explicit family context is required for #{family}; a synthesized default may be accepted by review.",
        blocking: true,
        proposed_context: { family_profile: deep_dup(family_profile) },
        action_offers: [
          { action: "accept_default_context", requires_context: false },
          { action: "provide_explicit_context", requires_context: true, payload_kind: "conformance_family_context" }
        ],
        default_action: "accept_default_context"
      }
    end
    private_class_method :family_context_review_request

    def diagnostic(severity, category, message, path: nil, review: nil)
      output = {
        severity: severity,
        category: category,
        message: message
      }
      output[:path] = path if path
      output[:review] = review if review
      output
    end
    private_class_method :diagnostic

    def compact_ruleset_identifier?(value)
      value.to_s.match?(/\A[A-Za-z][A-Za-z0-9_.-]*\z/)
    end
    private_class_method :compact_ruleset_identifier?

    def compact_ruleset_token?(value)
      value.to_s.match?(/\A[\x21\x24-\x7e]+\z/)
    end
    private_class_method :compact_ruleset_token?

    def compact_ruleset_known_directive?(value)
      COMPACT_RULESET_SINGLETON_DIRECTIVES.include?(value) ||
        COMPACT_RULESET_REPEATABLE_KEYED_DIRECTIVES.include?(value)
    end
    private_class_method :compact_ruleset_known_directive?

    def compact_ruleset_diagnostic(message, path = nil)
      diagnostic("error", "configuration_error", message, path: path)
    end
    private_class_method :compact_ruleset_diagnostic

    def join_comma(values)
      values.join(", ")
    end
    private_class_method :join_comma

    def conformance_suite_selectors_equal?(left, right)
      left[:kind] == right[:kind] &&
        left.dig(:subject, :grammar) == right.dig(:subject, :grammar) &&
        left.dig(:subject, :variant) == right.dig(:subject, :variant)
    end
    private_class_method :conformance_suite_selectors_equal?
  end
end
