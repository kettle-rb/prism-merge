# frozen_string_literal: true

require "json"
require "version_gem"

require "ast/merge"
require_relative "git/version"

module Ast
  module Merge
    module Git
      PACKAGE_NAME = "ast-merge-git"
      MERGE_CONFLICT_CATEGORY = "merge_conflict"

      module_function

      def merge3(request)
        normalized = normalize_request(request)
        case normalize_language(normalized)
        when "json"
          merge3_json(normalized)
        else
          response(
            ok: false,
            request: normalized,
            diagnostics: [{
              severity: "error",
              category: "unsupported_feature",
              message: "ast-merge-git currently supports only json merge3."
            }]
          )
        end
      end

      def merge3_json(request)
        base = parse_json_role("base", request.fetch(:base_source))
        ours = parse_json_role("ours", request.fetch(:ours_source))
        theirs = parse_json_role("theirs", request.fetch(:theirs_source))
        conflicts = []
        merged = merge_json_value(base, ours, theirs, "", conflicts)
        if conflicts.any?
          return response(
            ok: false,
            request: request,
            conflicts: conflicts,
            diagnostics: [{
              severity: "error",
              category: MERGE_CONFLICT_CATEGORY,
              message: "merge3 found #{conflicts.length} unresolved conflict(s)."
            }]
          )
        end

        output = JSON.generate(merged)
        response(
          ok: true,
          request: request,
          merged_source: output,
          reparse_after_render: JSON.parse(output) && true,
          formatting_preservation: {
            line_diff_score: 1.0,
            character_diff_score: 1.0
          }
        )
      rescue JSON::ParserError => e
        response(
          ok: false,
          request: request,
          diagnostics: [{
            severity: "error",
            category: "parse_error",
            message: e.message
          }]
        )
      end

      def normalize_request(request)
        request.transform_keys(&:to_sym)
      end

      def response(ok:, request:, merged_source: nil, conflicts: [], diagnostics: [], fallbacks: [], reparse_after_render: nil, formatting_preservation: {})
        {
          ok: ok,
          merged_source: merged_source,
          conflicts: conflicts,
          diagnostics: diagnostics,
          fallbacks: fallbacks,
          profile: {
            profile_id: request[:profile_id].to_s,
            language: normalize_language(request),
            dialect: request[:dialect].to_s
          },
          render_report: {
            strategy: request[:render_policy].to_s.empty? ? "canonical" : request[:render_policy].to_s
          },
          formatting_preservation: {
            line_diff_score: 0.0,
            character_diff_score: 0.0
          }.merge(formatting_preservation),
          reparse_after_render: reparse_after_render
        }
      end

      def parse_json_role(role, source)
        JSON.parse(source)
      rescue JSON::ParserError => e
        raise JSON::ParserError, "#{role} parse error: #{e.message}"
      end

      def merge_json_value(base, ours, theirs, path, conflicts)
        return ours if ours == theirs
        return theirs if base == ours
        return ours if base == theirs
        return merge_json_objects(base, ours, theirs, path, conflicts) if base.is_a?(Hash) && ours.is_a?(Hash) && theirs.is_a?(Hash)

        add_conflict(conflicts, "edit_edit", path, "value changed differently in ours and theirs")
        ours
      end

      def merge_json_objects(base, ours, theirs, path, conflicts)
        base = base.transform_keys(&:to_s)
        ours = ours.transform_keys(&:to_s)
        theirs = theirs.transform_keys(&:to_s)
        keys = (base.keys | ours.keys | theirs.keys).sort
        keys.each_with_object({}) do |key, result|
          merged, keep = merge_json_entry(
            base.key?(key) ? base[key] : :__absent__,
            ours.key?(key) ? ours[key] : :__absent__,
            theirs.key?(key) ? theirs[key] : :__absent__,
            json_pointer_join(path, key),
            conflicts
          )
          result[key] = merged if keep
        end
      end

      def merge_json_entry(base, ours, theirs, path, conflicts)
        base_absent = base == :__absent__
        ours_absent = ours == :__absent__
        theirs_absent = theirs == :__absent__
        return [nil, false] if base_absent && ours_absent && theirs_absent
        return [theirs, true] if base_absent && ours_absent
        return [ours, true] if base_absent && theirs_absent
        return [ours, true] if base_absent && ours == theirs
        if base_absent
          add_conflict(conflicts, "add_add", path, "same path added differently in ours and theirs")
          return [ours, true]
        end
        return [nil, false] if ours_absent && theirs_absent
        return [nil, false] if ours_absent && base == theirs
        return [nil, false] if theirs_absent && base == ours
        if ours_absent
          add_conflict(conflicts, "delete_edit", path, "ours deleted a value that theirs edited")
          return [theirs, true]
        end
        if theirs_absent
          add_conflict(conflicts, "delete_edit", path, "theirs deleted a value that ours edited")
          return [ours, true]
        end

        [merge_json_value(base, ours, theirs, path, conflicts), true]
      end

      def add_conflict(conflicts, category, path, message)
        conflicts << {
          conflict_id: "conflict-#{conflicts.length + 1}",
          category: category,
          path: path.empty? ? "/" : path,
          message: message
        }
      end

      def json_pointer_join(parent, token)
        escaped = token.to_s.gsub("~", "~0").gsub("/", "~1")
        parent.empty? ? "/#{escaped}" : "#{parent}/#{escaped}"
      end

      def normalize_language(request)
        language = request[:language].to_s.strip.downcase
        return "json" if language == "json"
        return "json" if request[:path_name].to_s.downcase.end_with?(".json")

        language
      end
    end
  end
end

Ast::Merge::Git::Version.class_eval do
  extend VersionGem::Basic
end
