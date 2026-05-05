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
      kettle_config = kettle_jem_config(project_root)
      funding = compact_hash(urls: funding_urls(project_root, gemspec))
      facts[:funding] = funding unless funding.empty?
      facts[:ci] = {
        provider: "github_actions",
        default_branch: "main",
        ruby_versions: github_actions_ruby_versions(facts.fetch(:rubygems).fetch(:min_ruby, nil)),
        custom_workflows: github_actions_custom_workflows(project_root),
      }
      framework_matrix = github_actions_framework_matrix(kettle_config)
      facts[:ci][:framework_matrix] = framework_matrix unless framework_matrix.empty?
      facts
    end

    def recipe_pack(facts)
      recipes = [
        recipe_entry("readme_metadata", "README.md", "markdown", "supplied_readme_metadata_synchronization", facts: %w[package funding readme]),
        recipe_entry("changelog_unreleased", "CHANGELOG.md", "markdown", "changelog_unreleased_normalization", facts: %w[package changelog]),
        recipe_entry("generated_block_sync", "gemfiles/modular/shunted.gemfile", "text", "supplied_managed_text_block_replacement", facts: %w[package generated_blocks]),
        recipe_entry(
          "github_actions_ci",
          ".github/workflows/ci.yml",
          "yaml",
          "supplied_github_actions_workflow_synchronization",
          facts: %w[package rubygems ci]
        ),
      ]
      if facts.dig(:ci, :framework_matrix)
        recipes << recipe_entry(
          "github_actions_framework_ci",
          ".github/workflows/framework-ci.yml",
          "yaml",
          "supplied_github_actions_framework_workflow_synchronization",
          facts: %w[package rubygems ci]
        )
      end
      facts.dig(:ci, :custom_workflows).to_a.each do |workflow_path|
        recipes << recipe_entry(
          "github_actions_workflow_snippets_#{workflow_recipe_slug(workflow_path)}",
          workflow_path,
          "yaml",
          "supplied_github_actions_workflow_snippet_merge",
          facts: %w[ci]
        )
      end
      recipes << recipe_entry(
        "rakefile_scaffold_cleanup",
        "Rakefile",
        "generic_ast",
        "supplied_source_selector_deletion",
        provider_backend: "generic_structural_owners",
        facts: %w[rubygems rakefile],
        selectors: %w[rakefile_scaffold]
      )

      {
        name: "kettle-jem-core",
        version: 1,
        ecosystem: "rubygems",
        recipes: recipes,
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
      deletion = recipe.fetch(:name) == "rakefile_scaffold_cleanup" ? delete_rakefile_scaffold(original) : nil
      final = case recipe.fetch(:name)
      when "readme_metadata"
        synchronize_readme(original, facts)
      when "changelog_unreleased"
        normalize_changelog(original, facts)
      when "generated_block_sync"
        synchronize_managed_block(original, facts)
      when "github_actions_ci"
        synchronize_github_actions_ci(original, facts)
      when "github_actions_framework_ci"
        synchronize_github_actions_framework_ci(original, facts)
      when /\Agithub_actions_workflow_snippets_/
        synchronize_github_actions_workflow_snippets(original)
      when "rakefile_scaffold_cleanup"
        deletion.fetch(:content)
      else
        original
      end

      request = content_recipe_execution_request(
        recipe_name: recipe.fetch(:primitive),
        recipe_version: "1",
        relative_path: relative_path,
        provider_family: recipe.fetch(:provider_family),
        provider_backend: recipe[:provider_backend],
        template_content: "",
        destination_content: original,
        steps: [content_recipe_step(recipe)],
        runtime_context: recipe_runtime_context(recipe, facts, deletion),
        metadata: { packaging_recipe: recipe.fetch(:name), project_root: project_root.to_s },
      )
      changed = final != original
      step_report = content_recipe_step_report(recipe: recipe, request: request, original: original, final: final, changed: changed, deletion: deletion)
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
      step = {
        step_id: recipe.fetch(:name),
        step_kind: recipe.fetch(:primitive),
        name: recipe.fetch(:name),
        provider_family: recipe.fetch(:provider_family),
        metadata: { target_path: recipe.fetch(:target_path) },
      }
      step[:provider_backend] = recipe[:provider_backend] if recipe[:provider_backend]
      if recipe.fetch(:primitive) == "supplied_source_selector_deletion"
        step[:step_kind] = "native_policy"
        step[:policy] = {
          policy_kind: "delete_supplied_structural_owners",
          required_context: "delete_selectors",
          operation: "delete",
          selector_family: "structural_owner_range",
          normalize_blank_lines: true,
        }
      end
      step
    end

    def content_recipe_step_report(recipe:, request:, original:, final:, changed:, deletion: nil)
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
        metadata: step_report_metadata(recipe, deletion),
      }
    end

    def read_project_files(project_root, pack)
      pack.fetch(:recipes).to_h do |recipe|
        relative_path = recipe.fetch(:target_path)
        path = File.join(project_root, relative_path)
        [relative_path, File.exist?(path) ? File.read(path) : ""]
      end
    end

    def recipe_entry(name, target_path, provider_family, primitive, facts:, provider_backend: nil, selectors: [])
      {
        name: name,
        target_path: target_path,
        provider_family: provider_family,
        provider_backend: provider_backend,
        primitive: primitive,
        facts: facts,
        selectors: selectors,
      }
    end

    def recipe_runtime_context(recipe, facts, deletion)
      context = deep_dup(facts)
      if recipe.fetch(:primitive) == "supplied_source_selector_deletion" && deletion
        context[:delete_selectors] = deletion.fetch(:delete_selectors)
      end
      context
    end

    def step_report_metadata(recipe, deletion)
      metadata = { target_path: recipe.fetch(:target_path) }
      return metadata unless deletion

      metadata.merge(
        policy_kind: "delete_supplied_structural_owners",
        operation: "delete",
        consumed_context: "delete_selectors",
        deleted_ranges: deletion.fetch(:delete_selectors).length,
        deleted_selector_ids: deletion.fetch(:delete_selectors).map { |selector| selector.fetch(:selector_id) },
      )
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

    def github_actions_ruby_versions(min_ruby)
      floor = min_ruby.to_s[/\d+\.\d+/] || "3.1"
      candidates = %w[3.1 3.2 3.3 3.4]
      selected = candidates.select { |version| Gem::Version.new(version) >= Gem::Version.new(floor) }
      selected.empty? ? [floor] : selected
    end

    def github_actions_custom_workflows(project_root)
      workflow_root = File.join(project_root, ".github", "workflows")
      return [] unless Dir.exist?(workflow_root)

      Dir.glob(File.join(workflow_root, "*.{yml,yaml}")).filter_map do |path|
        relative_path = path.delete_prefix("#{project_root}/")
        next if %w[.github/workflows/ci.yml .github/workflows/framework-ci.yml].include?(relative_path)

        relative_path
      end.sort
    end

    def workflow_recipe_slug(workflow_path)
      workflow_path.gsub(/[^a-zA-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    def kettle_jem_config(project_root)
      path = File.join(project_root, ".kettle-jem.yml")
      return {} unless File.exist?(path)

      config = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      config.is_a?(Hash) ? config : {}
    end

    def github_actions_framework_matrix(config)
      workflows = config["workflows"]
      return {} unless workflows.is_a?(Hash) && workflows["preset"].to_s.strip.downcase == "framework"

      raw = workflows["framework_matrix"]
      return {} unless raw.is_a?(Hash)

      dimension = raw["dimension"].to_s.strip
      versions = raw["versions"]
      pattern = raw["gemfile_pattern"].to_s.strip
      return {} unless !dimension.empty? && versions.is_a?(Array) && !versions.empty? && !pattern.empty?

      normalized_versions = versions.map { |version| version.to_s.strip }.reject(&:empty?)
      return {} if normalized_versions.empty?

      {
        dimension: dimension,
        versions: normalized_versions,
        gemfile_pattern: pattern,
        include: normalized_versions.map do |version|
          gemfile = expand_framework_gemfile_pattern(pattern, version)
          { framework_version: version, gemfile: framework_gemfile_path(gemfile) }
        end,
      }
    end

    def expand_framework_gemfile_pattern(pattern, version)
      replacement = if pattern.include?("_{version}") || pattern.include?("{version}_")
        version.tr(".", "_")
      else
        version
      end
      pattern.gsub("{version}", replacement)
    end

    def framework_gemfile_path(gemfile)
      gemfile.include?("/") ? gemfile : "gemfiles/#{gemfile}"
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

    def delete_rakefile_scaffold(content)
      selectors = rakefile_scaffold_delete_selectors(content)
      {
        content: delete_line_ranges(content.to_s, selectors),
        delete_selectors: selectors,
      }
    end

    def rakefile_scaffold_delete_selectors(content)
      lines = content.to_s.lines
      selectors = []
      lines.each_with_index do |line, index|
        case line
        when /\A\s*require\s+["']bundler\/gem_tasks["']\s*(?:#.*)?\n?\z/
          selectors << rakefile_selector(
            "rakefile_scaffold_require_bundler_gem_tasks",
            index + 1,
            index + 1,
            "wrapper_selected_scaffold_require"
          )
        when /\A\s*require\s+["']rspec\/core\/rake_task["']\s*(?:#.*)?\n?\z/
          selectors << rakefile_selector(
            "rakefile_scaffold_require_rspec_core_rake_task",
            index + 1,
            index + 1,
            "wrapper_selected_scaffold_require"
          )
        when /\A\s*require\s+["']rubocop\/rake_task["']\s*(?:#.*)?\n?\z/
          selectors << rakefile_selector(
            "rakefile_scaffold_require_rubocop_rake_task",
            index + 1,
            index + 1,
            "wrapper_selected_scaffold_require"
          )
        when /\A\s*RSpec::Core::RakeTask\.new\b/
          selectors << rakefile_selector("rakefile_scaffold_rspec_task", index + 1, index + 1,
            "wrapper_selected_scaffold_task")
        when /\A\s*RuboCop::RakeTask\.new\b/
          selectors << rakefile_selector("rakefile_scaffold_rubocop_task", index + 1, index + 1,
            "wrapper_selected_scaffold_task")
        end
      end
      selectors.concat(rakefile_task_block_selectors(lines))
      selectors.sort_by { |selector| [selector.fetch(:start_line), selector.fetch(:end_line)] }
    end

    def rakefile_task_block_selectors(lines)
      selectors = []
      index = 0
      while index < lines.length
        line = lines[index]
        if line.match?(/\A\s*task\s+default:/) || line.match?(/\A\s*task\s+:default\b/)
          end_index = rakefile_block_end(lines, index)
          selectors << rakefile_selector("rakefile_scaffold_task_default", index + 1, end_index + 1,
            "wrapper_selected_scaffold_task")
          index = end_index + 1
          next
        end
        index += 1
      end
      selectors
    end

    def rakefile_block_end(lines, start_index)
      return start_index unless lines[start_index].match?(/\bdo\b/)

      depth = 0
      (start_index...lines.length).each do |index|
        stripped = lines[index].strip
        depth += 1 if stripped.match?(/\bdo\b/)
        return index if depth.positive? && stripped == "end" && (depth -= 1).zero?
        return index if depth.zero? && index > start_index && !stripped.empty?
      end
      lines.length - 1
    end

    def rakefile_selector(selector_id, start_line, end_line, reason)
      {
        selector_id: selector_id,
        selector_family: "structural_owner_range",
        start_line: start_line,
        end_line: end_line,
        reason: reason,
      }
    end

    def delete_line_ranges(content, selectors)
      lines = content.lines
      selectors.sort_by { |selector| -selector.fetch(:start_line) }.each do |selector|
        start_index = selector.fetch(:start_line) - 1
        end_index = selector.fetch(:end_line) - 1
        lines.slice!(start_index..end_index)
      end
      lines.join.gsub(/\n{3,}/, "\n\n")
    end

    def synchronize_github_actions_ci(_content, facts)
      package = facts.fetch(:package)
      ci = facts.fetch(:ci)
      ruby_versions = ci.fetch(:ruby_versions)
      ruby_matrix = ruby_versions.map { |version| "          - \"#{version}\"" }.join("\n")

      <<~YAML
        name: CI

        permissions:
          contents: read

        on:
          push:
            branches:
              - "#{ci.fetch(:default_branch)}"
              - "*-stable"
            tags:
              - "!*" # Do not execute on tags
          pull_request:
            branches:
              - "*"
          workflow_dispatch:

        concurrency:
          group: "${{ github.workflow }}-${{ github.ref }}"
          cancel-in-progress: true

        jobs:
          test:
            if: "!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')"
            name: Specs ${{ matrix.ruby }}
            runs-on: ubuntu-latest
            continue-on-error: ${{ endsWith(matrix.ruby, 'head') }}
            strategy:
              fail-fast: false
              matrix:
                ruby:
        #{ruby_matrix}
                rubygems:
                  - default
                bundler:
                  - default

            steps:
              - name: Checkout #{package.fetch(:name)}
                uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

              - name: Setup Ruby & RubyGems
                uses: ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0
                with:
                  ruby-version: "${{ matrix.ruby }}"
                  rubygems: "${{ matrix.rubygems }}"
                  bundler: "${{ matrix.bundler }}"
                  bundler-cache: true

              - name: Tests
                run: bundle exec rake
      YAML
    end

    def synchronize_github_actions_framework_ci(_content, facts)
      ci = facts.fetch(:ci)
      framework_matrix = ci.fetch(:framework_matrix)
      ruby_matrix = ci.fetch(:ruby_versions).map { |version| "          - \"#{version}\"" }.join("\n")
      include_matrix = framework_matrix.fetch(:include).map do |entry|
        [
          "          - framework_version: \"#{entry.fetch(:framework_version)}\"",
          "            gemfile: \"#{entry.fetch(:gemfile)}\"",
        ].join("\n")
      end.join("\n")
      dimension = framework_matrix.fetch(:dimension)
      label = dimension.split(/[-_]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join(" ")

      <<~YAML
        name: #{label} CI

        permissions:
          contents: read

        on:
          push:
            branches:
              - "#{ci.fetch(:default_branch)}"
              - "*-stable"
            tags:
              - "!*" # Do not execute on tags
          pull_request:
            branches:
              - "*"
          workflow_dispatch:

        concurrency:
          group: "${{ github.workflow }}-${{ github.ref }}"
          cancel-in-progress: true

        jobs:
          test:
            if: "!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')"
            name: Specs ${{ matrix.ruby }}@${{ matrix.framework_version }}
            runs-on: ubuntu-latest
            continue-on-error: ${{ endsWith(matrix.ruby, 'head') }}
            env:
              BUNDLE_GEMFILE: ${{ github.workspace }}/${{ matrix.gemfile }}
            strategy:
              fail-fast: false
              matrix:
                ruby:
        #{ruby_matrix}
                rubygems:
                  - default
                bundler:
                  - default
                include:
        #{include_matrix}

            steps:
              - name: Checkout
                uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

              - name: Setup Ruby & RubyGems
                uses: ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0
                with:
                  ruby-version: "${{ matrix.ruby }}"
                  rubygems: "${{ matrix.rubygems }}"
                  bundler: "${{ matrix.bundler }}"
                  bundler-cache: true

              - name: Tests for ${{ matrix.ruby }}@${{ matrix.framework_version }}
                run: bundle exec rake test
      YAML
    end

    def synchronize_github_actions_workflow_snippets(content)
      updated = ensure_workflow_top_level_section(
        content.to_s,
        "permissions",
        "permissions:\n  contents: read\n\n",
        before: "on"
      )
      updated = ensure_workflow_top_level_section(
        updated,
        "concurrency",
        "concurrency:\n  group: \"${{ github.workflow }}-${{ github.ref }}\"\n  cancel-in-progress: true\n\n",
        before: "jobs"
      )
      updated = append_github_actions_coverage_steps(updated) if github_actions_coverage_enabled?(updated)
      update_github_actions_pins(updated)
    end

    def github_actions_coverage_enabled?(content)
      content.match?(/K_SOUP_COV_DO:\s*["']?true["']?/)
    end

    def append_github_actions_coverage_steps(content)
      return content if content.include?("Upload coverage to Coveralls") || content.include?("Upload coverage to CodeCov")

      lines = content.lines
      steps_index = lines.index { |line| line.match?(/^    steps:\s*$/) }
      return content unless steps_index

      insert_index = lines.length
      ((steps_index + 1)...lines.length).each do |index|
        line = lines[index]
        next if line.strip.empty?
        next unless line.match?(/^\S|^  \S|^    \S/) && !line.match?(/^      /)

        insert_index = index
        break
      end
      lines.insert(insert_index, github_actions_coverage_steps)
      lines.join
    end

    def github_actions_coverage_steps
      <<~YAML.lines.map { |line| line.strip.empty? ? line : "      #{line}" }.join
        - name: Upload coverage to Coveralls
          if: ${{ !env.ACT }}
          uses: coverallsapp/github-action@0a51d2e0b5417d06e4ecceb534aec87defc53926 # main
          with:
            github-token: ${{ secrets.GITHUB_TOKEN }}
          continue-on-error: ${{ matrix.experimental != 'false' }}

        - name: Upload coverage to QLTY
          if: ${{ !env.ACT }}
          uses: qltysh/qlty-action/coverage@a19242102d17e497f437d7466aa01b528537e899 # v2.2.0
          with:
            token: ${{secrets.QLTY_COVERAGE_TOKEN}}
            files: coverage/.resultset.json
          continue-on-error: ${{ matrix.experimental != 'false' }}

        - name: Upload coverage to CodeCov
          if: ${{ !env.ACT }}
          uses: codecov/codecov-action@57e3a136b779b570ffcdbf80b3bdc90e7fab3de2 # v6.0.0
          with:
            use_oidc: true
            fail_ci_if_error: false
            files: coverage/lcov.info,coverage/coverage.xml
            verbose: true

        - name: Code Coverage Summary Report
          if: ${{ !env.ACT && github.event_name == 'pull_request' }}
          uses: irongut/CodeCoverageSummary@51cc3a756ddcd398d447c044c02cb6aa83fdae95 # v1.3.0
          with:
            filename: ./coverage/coverage.xml
            badge: true
            fail_below_min: true
            format: markdown
            hide_branch_rate: false
            hide_complexity: true
            indicators: true
            output: both
            thresholds: '100 100'
          continue-on-error: ${{ matrix.experimental != 'false' }}

        - name: Add Coverage PR Comment
          uses: marocchino/sticky-pull-request-comment@0ea0beb66eb9baf113663a64ec522f60e49231c0 # v3.0.4
          if: ${{ !env.ACT && github.event_name == 'pull_request' }}
          with:
            recreate: true
            path: code-coverage-results.md
          continue-on-error: ${{ matrix.experimental != 'false' }}
      YAML
    end

    def ensure_workflow_top_level_section(content, key, section, before:)
      return content if content.match?(/^#{Regexp.escape(key)}:/)

      lines = content.lines
      index = lines.index { |line| line.match?(/^#{Regexp.escape(before)}:/) }
      if index
        prepared_section = index.zero? || lines[index - 1].strip.empty? ? section : "\n#{section}"
        lines.insert(index, prepared_section)
      else
        lines << "\n" unless lines.empty? || lines.last == "\n"
        lines << section
      end
      lines.join
    end

    def update_github_actions_pins(content)
      github_actions_step_pins.reduce(content) do |updated, (action_prefix, pinned_value)|
        updated.gsub(/^(\s*(?:-\s*)?uses:\s*)#{Regexp.escape(action_prefix)}@\S+(?:\s+#.*)?$/) do
          "#{$1}#{pinned_value}"
        end
      end
    end

    def github_actions_step_pins
      {
        "actions/checkout" => "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2",
        "ruby/setup-ruby" => "ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0",
        "coverallsapp/github-action" => "coverallsapp/github-action@0a51d2e0b5417d06e4ecceb534aec87defc53926 # main",
        "qltysh/qlty-action/coverage" => "qltysh/qlty-action/coverage@a19242102d17e497f437d7466aa01b528537e899 # v2.2.0",
        "codecov/codecov-action" => "codecov/codecov-action@57e3a136b779b570ffcdbf80b3bdc90e7fab3de2 # v6.0.0",
        "irongut/CodeCoverageSummary" => "irongut/CodeCoverageSummary@51cc3a756ddcd398d447c044c02cb6aa83fdae95 # v1.3.0",
        "marocchino/sticky-pull-request-comment" => "marocchino/sticky-pull-request-comment@0ea0beb66eb9baf113663a64ec522f60e49231c0 # v3.0.4",
      }
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
