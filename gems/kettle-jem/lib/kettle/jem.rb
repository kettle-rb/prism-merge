# frozen_string_literal: true

require "fileutils"
require "yaml"
require "ast/merge"
require_relative "jem/version"

module Kettle
  module Jem
    PACKAGE_NAME = "kettle-jem"
    CONTENT_RECIPE_TRANSPORT_VERSION = Ast::Merge::STRUCTURED_EDIT_TRANSPORT_VERSION
    MANAGED_BLOCK_OPEN = "# <<kettle-jem:generated>> do not edit below this line"
    MANAGED_BLOCK_CLOSE = "# <</kettle-jem:generated>>"

    module_function

    def discover_facts(project_root)
      gemspec_path = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
      raise ArgumentError, "no gemspec found in #{project_root}" unless gemspec_path

      gemspec = File.read(gemspec_path)
      name = extract_gemspec_assignment(gemspec, "spec.name") || File.basename(gemspec_path, ".gemspec")
      source_url = extract_metadata_value(gemspec, "source_code_uri") ||
        extract_gemspec_assignment(gemspec, "spec.homepage")

      facts = {
        package: compact_hash(
          ecosystem: "rubygems",
          name: name,
          slug: name,
          description: extract_gemspec_assignment(gemspec, "spec.description") ||
            extract_gemspec_assignment(gemspec, "spec.summary"),
          homepage_url: extract_gemspec_assignment(gemspec, "spec.homepage"),
          source_url: source_url,
          license_expression: Array(extract_gemspec_array(gemspec, "spec.licenses")).join(" OR "),
        ),
        rubygems: compact_hash(
          gemspec_path: File.basename(gemspec_path),
          namespace: classify_namespace(name),
          min_ruby: extract_gemspec_assignment(gemspec, "spec.required_ruby_version"),
        ),
      }
      funding = compact_hash(urls: funding_urls(project_root, gemspec))
      facts[:funding] = funding unless funding.empty?
      facts
    end

    def recipe_pack(facts)
      {
        name: "kettle-jem-core",
        version: 1,
        ecosystem: "rubygems",
        recipes: [
          recipe_entry("readme_metadata", "README.md", "markdown", "supplied_readme_metadata_synchronization", facts: %w[package funding readme]),
          recipe_entry("changelog_unreleased", "CHANGELOG.md", "markdown", "changelog_unreleased_normalization", facts: %w[package changelog]),
          recipe_entry("generated_block_sync", "gemfiles/modular/shunted.gemfile", "text", "supplied_managed_text_block_replacement", facts: %w[package generated_blocks]),
        ],
      }
    end

    def plan_project(project_root)
      facts = discover_facts(project_root)
      pack = recipe_pack(facts)
      files = read_project_files(project_root, pack)
      recipe_reports = pack.fetch(:recipes).map do |recipe|
        execute_recipe(project_root: project_root, recipe: recipe, facts: facts, files: files)
      end
      changed_files = recipe_reports.filter_map { |report| report[:relative_path] if report[:changed] }.sort

      {
        mode: "plan",
        ready: true,
        facts: facts,
        recipe_pack: pack,
        recipe_reports: recipe_reports,
        changed_files: changed_files,
        diagnostics: recipe_reports.flat_map { |report| report[:diagnostics] },
      }
    end

    def apply_project(project_root)
      report = plan_project(project_root).merge(mode: "apply")
      report.fetch(:recipe_reports).each do |recipe_report|
        next unless recipe_report[:changed]

        path = File.join(project_root, recipe_report.fetch(:relative_path))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, recipe_report.fetch(:final_content))
      end
      report
    end

    def content_recipe_execution_request(recipe_name:, recipe_version:, relative_path:, provider_family:,
      template_content:, destination_content:, steps:, provider_backend: nil, runtime_context: nil, metadata: nil)
      compact_hash(
        recipe_name: recipe_name.to_s,
        recipe_version: recipe_version.to_s,
        relative_path: relative_path.to_s,
        provider_family: provider_family.to_s,
        provider_backend: provider_backend&.to_s,
        template_content: template_content.to_s,
        destination_content: destination_content.to_s,
        steps: deep_dup(steps),
        runtime_context: deep_dup(runtime_context || {}),
        metadata: deep_dup(metadata || {}),
      )
    end

    def content_recipe_execution_request_envelope(request)
      {
        kind: "content_recipe_execution_request",
        version: CONTENT_RECIPE_TRANSPORT_VERSION,
        request: deep_dup(request),
      }
    end

    def content_recipe_execution_report(request:, final_content:, changed:, step_reports:, diagnostics:, metadata: nil)
      compact_hash(
        request: deep_dup(request),
        final_content: final_content.to_s,
        changed: changed ? true : false,
        step_reports: deep_dup(step_reports),
        diagnostics: deep_dup(diagnostics),
        metadata: deep_dup(metadata || {}),
      )
    end

    def content_recipe_execution_report_envelope(report)
      {
        kind: "content_recipe_execution_report",
        version: CONTENT_RECIPE_TRANSPORT_VERSION,
        report: deep_dup(report),
      }
    end

    def synchronize_readme(content, facts)
      package = facts.fetch(:package)
      lines = content.to_s.split("\n", -1)
      heading = "# #{package.fetch(:name)}"
      h1_index = lines.index { |line| line.start_with?("# ") }
      if h1_index
        lines[h1_index] = heading
      else
        lines.unshift(heading, "")
      end
      replace_markdown_managed_block(lines.join("\n"), "kettle-jem:metadata", readme_metadata_block(facts))
    end

    def normalize_changelog(content, facts)
      text = content.to_s
      title = "# Changelog"
      text = "#{title}\n\n#{text}" unless text.lines.first&.start_with?("# ")
      return ensure_trailing_newline(text) if text.match?(/^##\s+\[?Unreleased\]?/i)

      lines = text.split("\n", -1)
      insert_at = lines.index { |line| line.start_with?("## ") } || lines.length
      section = [
        "## [Unreleased]",
        "",
        "### Added",
        "",
        "### Changed",
        "",
        "### Fixed",
        "",
      ]
      lines.insert(insert_at, *section)
      ensure_trailing_newline(lines.join("\n").gsub(/\n{3,}/, "\n\n"))
    end

    def synchronize_managed_block(content, facts)
      replacement = [
        MANAGED_BLOCK_OPEN,
        "# package: #{facts.fetch(:package).fetch(:name)}",
        "# generated by kettle-jem vNext",
        MANAGED_BLOCK_CLOSE,
        "",
      ].join("\n")
      replace_text_managed_block(content.to_s, replacement)
    end

    def execute_recipe(project_root:, recipe:, facts:, files:)
      relative_path = recipe.fetch(:target_path)
      original = files.fetch(relative_path, "")
      final = case recipe.fetch(:name)
      when "readme_metadata"
        synchronize_readme(original, facts)
      when "changelog_unreleased"
        normalize_changelog(original, facts)
      when "generated_block_sync"
        synchronize_managed_block(original, facts)
      else
        original
      end

      request = content_recipe_execution_request(
        recipe_name: recipe.fetch(:primitive),
        recipe_version: "1",
        relative_path: relative_path,
        provider_family: recipe.fetch(:provider_family),
        template_content: "",
        destination_content: original,
        steps: [content_recipe_step(recipe)],
        runtime_context: facts,
        metadata: { packaging_recipe: recipe.fetch(:name), project_root: project_root.to_s },
      )
      changed = final != original
      step_report = content_recipe_step_report(recipe: recipe, request: request, original: original, final: final, changed: changed)
      report = content_recipe_execution_report(
        request: request,
        final_content: final,
        changed: changed,
        step_reports: [step_report],
        diagnostics: [],
        metadata: { packaging_recipe: recipe.fetch(:name) },
      )

      {
        recipe_name: recipe.fetch(:name),
        relative_path: relative_path,
        changed: changed,
        request_envelope: content_recipe_execution_request_envelope(request),
        report_envelope: content_recipe_execution_report_envelope(report),
        final_content: final,
        diagnostics: [],
      }
    end

    def content_recipe_step(recipe)
      {
        step_id: recipe.fetch(:name),
        step_kind: recipe.fetch(:primitive),
        name: recipe.fetch(:name),
        provider_family: recipe.fetch(:provider_family),
        metadata: { target_path: recipe.fetch(:target_path) },
      }
    end

    def content_recipe_step_report(recipe:, request:, original:, final:, changed:)
      operation_profile = Ast::Merge.structured_edit_operation_profile(
        operation_kind: recipe.fetch(:primitive),
        known_operation_kind: true,
        source_requirement: "destination_content",
        destination_requirement: "relative_path",
        replacement_source: "runtime_context",
        captures_source_text: false,
        supports_if_missing: true,
        operation_family: "kettle-jem",
      )
      result = Ast::Merge.structured_edit_result(
        operation_kind: recipe.fetch(:primitive),
        updated_content: final,
        changed: changed,
        operation_profile: operation_profile,
      )
      application = Ast::Merge.structured_edit_application(request: request, result: result)
      {
        step_id: recipe.fetch(:name),
        step_kind: recipe.fetch(:primitive),
        status: changed ? "applied" : "unchanged",
        changed: changed,
        input_content: original,
        output_content: final,
        application: application,
        diagnostics: [],
        metadata: { target_path: recipe.fetch(:target_path) },
      }
    end

    def read_project_files(project_root, pack)
      pack.fetch(:recipes).to_h do |recipe|
        relative_path = recipe.fetch(:target_path)
        path = File.join(project_root, relative_path)
        [relative_path, File.exist?(path) ? File.read(path) : ""]
      end
    end

    def recipe_entry(name, target_path, provider_family, primitive, facts:)
      {
        name: name,
        target_path: target_path,
        provider_family: provider_family,
        primitive: primitive,
        facts: facts,
        selectors: [],
      }
    end

    def extract_gemspec_assignment(source, field)
      match = source.match(/#{Regexp.escape(field)}\s*=\s*["']([^"']*)["']/)
      match && match[1]
    end

    def extract_gemspec_array(source, field)
      match = source.match(/#{Regexp.escape(field)}\s*=\s*\[([^\]]*)\]/m)
      return [] unless match

      match[1].scan(/["']([^"']+)["']/).flatten
    end

    def extract_metadata_value(source, key)
      match = source.match(/spec\.metadata\[\s*["']#{Regexp.escape(key)}["']\s*\]\s*=\s*["']([^"']*)["']/)
      match && match[1]
    end

    def funding_urls(project_root, gemspec_source)
      urls = [extract_metadata_value(gemspec_source, "funding_uri")]
      path = File.join(project_root, ".github", "FUNDING.yml")
      urls.concat(github_funding_urls(path)) if File.exist?(path)

      urls.compact.uniq.sort
    end

    def github_funding_urls(path)
      funding = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      return [] unless funding.is_a?(Hash)

      funding.flat_map do |platform, value|
        github_funding_platform_urls(platform.to_s, Array(value).compact)
      end
    end

    def github_funding_platform_urls(platform, values)
      values.filter_map do |value|
        handle = value.to_s.strip.delete_prefix("@")
        next if handle.empty?

        case platform
        when "buy_me_a_coffee"
          "https://www.buymeacoffee.com/#{handle}"
        when "custom"
          handle if handle.match?(%r{\Ahttps?://})
        when "github"
          "https://github.com/sponsors/#{handle}"
        when "issuehunt"
          "https://issuehunt.io/u/#{handle}"
        when "ko_fi"
          "https://ko-fi.com/#{handle}"
        when "liberapay"
          "https://liberapay.com/#{handle}/donate"
        when "open_collective"
          "https://opencollective.com/#{handle}"
        when "patreon"
          "https://patreon.com/#{handle}"
        when "polar"
          "https://polar.sh/#{handle}"
        when "thanks_dev"
          "https://thanks.dev/#{handle}"
        when "tidelift"
          "https://tidelift.com/funding/github/#{handle}"
        end
      end
    end

    def classify_namespace(name)
      name.to_s.split(/[-_]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join("::")
    end

    def readme_metadata_block(facts)
      package = facts.fetch(:package)
      funding_urls = facts.fetch(:funding, {}).fetch(:urls, [])
      rows = [
        ["Package", package[:name]],
        ["Description", package[:description]],
        ["Homepage", package[:homepage_url]],
        ["Source", package[:source_url]],
        ["License", package[:license_expression]],
        ["Funding", funding_urls.join(", ")],
      ].reject { |(_, value)| value.to_s.empty? }

      [
        "<!-- kettle-jem:metadata:start -->",
        "| Field | Value |",
        "|---|---|",
        *rows.map { |field, value| "| #{field} | #{value} |" },
        "<!-- kettle-jem:metadata:end -->",
      ].join("\n")
    end

    def replace_markdown_managed_block(content, marker, replacement)
      open = "<!-- #{marker}:start -->"
      close = "<!-- #{marker}:end -->"
      replace_between_markers(content, open, close, replacement) do
        [content.rstrip, "", replacement, ""].join("\n")
      end
    end

    def replace_text_managed_block(content, replacement)
      replace_between_markers(content, MANAGED_BLOCK_OPEN, MANAGED_BLOCK_CLOSE, replacement) do
        [content.rstrip, replacement].reject(&:empty?).join("\n")
      end
    end

    def replace_between_markers(content, open_marker, close_marker, replacement)
      open_index = content.index(open_marker)
      close_index = content.index(close_marker)
      return yield unless open_index && close_index && close_index >= open_index

      close_end = close_index + close_marker.length
      close_end += 1 if content[close_end] == "\n"
      "#{content[0...open_index]}#{replacement}\n#{content[close_end..]}"
    end

    def ensure_trailing_newline(text)
      text.end_with?("\n") ? text : "#{text}\n"
    end

    def compact_hash(hash)
      hash.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end
