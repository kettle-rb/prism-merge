# frozen_string_literal: true

require "ast/crispr"
require "markly/merge"
require "version_gem"
require_relative "markly/version"

module Ast
  module Crispr
    module Markdown
      module Markly
        class Error < StandardError; end

        class Adapter
          Location = Struct.new(:start_line, :end_line, keyword_init: true)
          HeadingSectionOwner = Struct.new(
            :location,
            :heading_text,
            :heading_source,
            :level,
            :base,
            keyword_init: true,
          )

          def read_ast(document)
            analysis = ::Markly::Merge::FileAnalysis.new(document.content)
            return analysis if analysis.valid?

            raise Ast::Crispr::Error.new("Unable to read structural owners from #{document.source_label}", details: {source_label: document.source_label})
          end

          def structural_owners(document, owner_scope: :shared_default)
            analysis = document.ast
            case owner_scope
            when :shared_default, :heading_sections
              build_heading_sections(analysis)
            else
              raise Ast::Crispr::Error.new("Unsupported CRISPR owner scope", details: {owner_scope: owner_scope})
            end
          end

          def comment_regions_for(_document, _owner, region: :leading, owner_scope: :shared_default)
            raise Ast::Crispr::Error.new(
              "Unsupported CRISPR comment region",
              details: {region: region, owner_scope: owner_scope},
            )
          end

          def comment_region_text(_document, _comment_region)
            raise Ast::Crispr::Error.new("Markdown CRISPR adapter does not expose comment regions")
          end

          def structure_profile(owner_scope: :shared_default)
            case owner_scope
            when :shared_default, :heading_sections
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :heading_sections,
                supported_comment_regions: [],
                metadata: {adapter: :markly},
              )
            else
              raise Ast::Crispr::Error.new("Unsupported CRISPR owner scope", details: {owner_scope: owner_scope})
            end
          end

          private

          def build_heading_sections(analysis)
            headings = Array(analysis.statements).filter_map do |statement|
              next unless heading_statement?(statement)

              build_heading_owner(statement, analysis)
            end

            headings.each_with_index.map do |owner, index|
              branch_end_line = branch_end_line(headings, index, analysis)
              HeadingSectionOwner.new(
                location: Location.new(start_line: owner.location.start_line, end_line: branch_end_line),
                heading_text: owner.heading_text,
                heading_source: owner.heading_source,
                level: owner.level,
                base: owner.base,
              )
            end
          end

          def heading_statement?(statement)
            merge_type = if statement.respond_to?(:merge_type)
              statement.merge_type
            else
              unwrap_markdown_statement(statement)&.type
            end

            merge_type.to_s == "heading" || merge_type.to_s == "header"
          end

          def build_heading_owner(statement, analysis)
            node = unwrap_markdown_statement(statement)
            position = node&.source_position
            return unless node && position

            heading_source = analysis.source_range(position[:start_line], position[:end_line]).sub(/\n\z/, "")
            heading_text = node.to_plaintext.to_s.sub(/\n+\z/, "")
            HeadingSectionOwner.new(
              location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
              heading_text: heading_text,
              heading_source: heading_source,
              level: node.header_level,
              base: normalize_heading_base(heading_text),
            )
          rescue StandardError
            nil
          end

          def branch_end_line(headings, index, analysis)
            current = headings[index]
            cursor = index + 1
            while cursor < headings.length
              return headings[cursor].location.start_line - 1 if headings[cursor].level <= current.level

              cursor += 1
            end

            analysis.source.to_s.lines.length
          end

          def unwrap_markdown_statement(statement)
            if defined?(Ast::Merge::NodeTyping)
              Ast::Merge::NodeTyping.unwrap(statement)
            else
              statement
            end
          rescue StandardError
            statement
          end

          def normalize_heading_base(text)
            text.to_s.sub(/\A(?:\d\uFE0F?\u20E3|[^[:alnum:][:space:]])+[ \t]*/u, "").strip.downcase
          end
        end

        module Selectors
          module_function

          def heading_section(heading_text:, level: nil, id: nil, limit: nil, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || "heading_section_#{heading_text}",
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Markdown::Markly.adapter,
                owner_scope: :heading_sections,
                selector_kind: :heading_section,
                selection_intent: :section_branch,
                include_trailing_gap: false,
              ).merge(options),
              locate: lambda do |context|
                context.structural_owners(owner_scope: :heading_sections).filter_map do |owner|
                  next unless owner.heading_text.to_s.strip == heading_text.to_s.strip
                  next if level && owner.level != level

                  Ast::Crispr::Match.new(
                    node: owner,
                    start_line: owner.location.start_line,
                    end_line: owner.location.end_line,
                    metadata: {
                      start_boundary: :owner_start,
                      end_boundary: :owner_end,
                      payload_kind: :section_branch,
                      heading_text: owner.heading_text,
                      level: owner.level,
                      base: owner.base,
                    },
                  )
                end
              end,
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

Ast::Crispr::Markdown::Markly::Version.class_eval do
  extend VersionGem::Basic
end
