# frozen_string_literal: true

require "ast/merge"
require_relative "crispr/version"

module Ast
  module Crispr
    PACKAGE_NAME = "ast-crispr"

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
            "ast-merge structured-edit contract anchor"
          ],
          future_exports: [
            "limit helpers",
            "match profile helpers",
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
    end
  end
end

