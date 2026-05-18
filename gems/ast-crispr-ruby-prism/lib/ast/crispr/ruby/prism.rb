# frozen_string_literal: true

require "ast/crispr"
require "prism"
require "version_gem"
require_relative "prism/version"

module Ast
  module Crispr
    module Ruby
      module Prism
        class Error < StandardError; end

        module Utils
          module_function

          def parse_with_comments(source)
            ::Prism.parse(source)
          end

          def extract_statements(body_node)
            return [] unless body_node

            if body_node.is_a?(::Prism::StatementsNode)
              body_node.body.compact
            else
              [body_node].compact
            end
          end

          def find_leading_comments(parse_result, current_stmt, prev_stmt, body_node)
            start_line = prev_stmt ? prev_stmt.location.end_line : body_node.location.start_line
            end_line = current_stmt.location.start_line

            parse_result.comments.select do |comment|
              comment.location.start_line > start_line &&
                comment.location.start_line < end_line
            end
          end
        end

        class Adapter
          def read_ast(document)
            result = Utils.parse_with_comments(document.content)
            return result if result.success?

            raise Ast::Crispr::Error.new("Unable to read structural owners from #{document.source_label}", details: {source_label: document.source_label})
          end

          def structural_owners(document, owner_scope: :shared_default)
            parse_result = document.ast
            case owner_scope
            when :shared_default, :line_bound_statements, :top_level_statements
              Utils.extract_statements(parse_result.value.statements)
            else
              raise Ast::Crispr::Error.new("Unsupported CRISPR owner scope", details: {owner_scope: owner_scope})
            end
          end

          def comment_regions_for(document, owner, region: :leading, owner_scope: :shared_default)
            parse_result = document.ast
            owners = structural_owners(document, owner_scope: owner_scope)
            index = owners.index(owner)
            return [] unless index

            case region
            when :leading
              previous_owner = index.positive? ? owners[index - 1] : nil
              if previous_owner
                Utils.find_leading_comments(parse_result, owner, previous_owner, parse_result.value.statements)
              else
                parse_result.comments.select { |comment| comment.location.start_line < owner.location.start_line }
              end
            else
              raise Ast::Crispr::Error.new("Unsupported CRISPR comment region", details: {region: region})
            end
          end

          def comment_region_text(document, comment_region)
            document.location_slice(comment_region.location).rstrip
          end

          def structure_profile(owner_scope: :shared_default)
            case owner_scope
            when :shared_default, :line_bound_statements, :top_level_statements
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :line_bound_statements,
                supported_comment_regions: [:leading],
                metadata: {adapter: :prism},
              )
            else
              raise Ast::Crispr::Error.new("Unsupported CRISPR owner scope", details: {owner_scope: owner_scope})
            end
          end
        end

        module Selectors
          module_function

          def owner_filter(id:, limit: nil, owner_scope: :shared_default, include_trailing_gap: false, metadata: {}, &block)
            Ast::Crispr::Selectors.owner_filter(
              id: id,
              limit: limit,
              owner_scope: owner_scope,
              include_trailing_gap: include_trailing_gap,
              adapter: Ast::Crispr::Ruby::Prism.adapter,
              metadata: metadata,
              &block
            )
          end

          def comment_region_owned_owner(marker:, id: nil, limit: nil, owner_scope: :shared_default, comment_region: :leading, include_trailing_gap: true, metadata: {}, **options)
            Ast::Crispr::Selectors.comment_region_owned_owner(
              marker: marker,
              id: id,
              limit: limit,
              owner_scope: owner_scope,
              comment_region: comment_region,
              include_trailing_gap: include_trailing_gap,
              adapter: Ast::Crispr::Ruby::Prism.adapter,
              metadata: metadata,
              **options,
            )
          end
        end

        Targets = Selectors

        class << self
          def adapter
            @adapter ||= Adapter.new
          end

          def document_context(content:, source_label: "source", metadata: {}, **options)
            Ast::Crispr::DocumentContext.new(
              content: content,
              source_label: source_label,
              adapter: adapter,
              metadata: metadata,
              **options,
            )
          end
        end
      end
    end
  end
end

Ast::Crispr::Ruby::Prism::Version.class_eval do
  extend VersionGem::Basic
end
