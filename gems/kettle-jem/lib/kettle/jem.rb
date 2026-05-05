# frozen_string_literal: true

require "fileutils"
require "token/resolver"
require "yaml"
require "ast/merge"
require_relative "jem/version"

module Kettle
  module Jem
    PACKAGE_NAME = "kettle-jem"
    CONTENT_RECIPE_TRANSPORT_VERSION = Ast::Merge::STRUCTURED_EDIT_TRANSPORT_VERSION
    MANAGED_BLOCK_OPEN = "# <<kettle-jem:generated>> do not edit below this line"
    MANAGED_BLOCK_CLOSE = "# <</kettle-jem:generated>>"
    OBSOLETE_GITHUB_WORKFLOWS = %w[ancient.yml legacy.yml supported.yml unsupported.yml main.yml hoary.yml].freeze
    OPENCOLLECTIVE_DISABLED_FILES = %w[.opencollective.yml .github/workflows/opencollective.yml].freeze
    FILE_DELETION_PRIMITIVES = %w[supplied_obsolete_file_deletion supplied_disabled_opencollective_file_deletion].freeze
    TEMPLATE_TOKEN_CONFIG = Token::Resolver::Config.new(separators: ["|", ":"]).freeze
    FORGE_USER_ENV_KEYS = {
      gh_user: "KJ_GH_USER",
      gl_user: "KJ_GL_USER",
      cb_user: "KJ_CB_USER",
      sh_user: "KJ_SH_USER",
    }.freeze
    FUNDING_TOKEN_ENV_KEYS = {
      patreon: "KJ_FUNDING_PATREON",
      kofi: "KJ_FUNDING_KOFI",
      paypal: "KJ_FUNDING_PAYPAL",
      buymeacoffee: "KJ_FUNDING_BUYMEACOFFEE",
      polar: "KJ_FUNDING_POLAR",
      liberapay: "KJ_FUNDING_LIBERAPAY",
      issuehunt: "KJ_FUNDING_ISSUEHUNT",
    }.freeze
    SOCIAL_TOKEN_ENV_KEYS = {
      mastodon: "KJ_SOCIAL_MASTODON",
      bluesky: "KJ_SOCIAL_BLUESKY",
      linktree: "KJ_SOCIAL_LINKTREE",
      devto: "KJ_SOCIAL_DEVTO",
    }.freeze
    APACHE_LICENSE_COMPAT_CATEGORIES = {
      "Apache-2.0" => :a,
      "MIT" => :a,
      "AGPL-3.0-only" => :x,
      "PolyForm-Noncommercial-1.0.0" => :x,
      "PolyForm-Small-Business-1.0.0" => :x,
      "LicenseRef-Big-Time-Public-License" => :x,
    }.freeze
    APACHE_LICENSE_COMPAT_BADGE_DATA = {
      a: {
        alt: "Apache license compatibility: Category A",
        label: "Apache_Compatible:_Category_A",
        message: "\u2713",
        color: "259D6C",
        ref: "https://www.apache.org/legal/resolved.html#category-a",
      },
      b: {
        alt: "Apache license compatibility: Category B",
        label: "Apache_Maybe_Compatible:_Category_B",
        message: "?",
        color: "D9A407",
        ref: "https://www.apache.org/legal/resolved.html#category-b",
      },
      x: {
        alt: "Apache license compatibility: Category X",
        label: "Apache_Incompatible:_Category_X",
        message: "\u2717",
        color: "C0392B",
        ref: "https://www.apache.org/legal/resolved.html#category-x",
      },
      unknown: {
        alt: "Apache license compatibility: Unknown",
        label: "Apache_Compatibility",
        message: "Unknown",
        color: "6C757D",
        ref: "https://www.apache.org/legal/resolved.html",
      },
    }.freeze

    module_function

    def discover_facts(project_root, env: ENV)
      gemspec_path = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
      raise ArgumentError, "no gemspec found in #{project_root}" unless gemspec_path

      gemspec = File.read(gemspec_path)
      name = extract_gemspec_assignment(gemspec, "spec.name") || File.basename(gemspec_path, ".gemspec")
      source_url = extract_metadata_value(gemspec, "source_code_uri") ||
        extract_gemspec_assignment(gemspec, "spec.homepage")

      kettle_config = kettle_jem_config(project_root)
      author = author_facts(gemspec, kettle_config, env)
      license = license_facts(kettle_config, extract_gemspec_array(gemspec, "spec.licenses"), author_email: author[:email])
      facts = {
        package: compact_hash(
          ecosystem: "rubygems",
          name: name,
          slug: name,
          description: extract_gemspec_assignment(gemspec, "spec.description") ||
            extract_gemspec_assignment(gemspec, "spec.summary"),
          homepage_url: extract_gemspec_assignment(gemspec, "spec.homepage"),
          source_url: source_url,
          license_expression: license[:expression],
        ),
        rubygems: compact_hash(
          gemspec_path: File.basename(gemspec_path),
          namespace: classify_namespace(name),
          min_ruby: extract_gemspec_assignment(gemspec, "spec.required_ruby_version"),
        ),
      }
      facts[:author] = author unless author.empty?
      forge = forge_facts(kettle_config, env)
      facts[:forge] = forge unless forge.empty?
      social = social_facts(kettle_config, env)
      facts[:social] = social unless social.empty?
      opencollective_policy = opencollective_policy(kettle_config, env)
      opencollective_disabled = opencollective_policy.fetch(:disabled)
      open_collective_org = opencollective_org(project_root, env, opencollective_disabled: opencollective_disabled)
      funding = compact_hash(
        urls: funding_urls(
          project_root,
          gemspec,
          name,
          opencollective_disabled: opencollective_disabled,
          open_collective_org: open_collective_org && open_collective_org.fetch(:org)
        )
      )
      funding_tokens = funding_platform_token_facts(kettle_config, env)
      funding[:platform_tokens] = funding_tokens unless funding_tokens.empty?
      funding[:open_collective_disabled] = true if opencollective_disabled
      funding[:open_collective_disabled_source] = opencollective_policy[:source] if opencollective_disabled
      if open_collective_org
        funding[:open_collective_org] = open_collective_org.fetch(:org)
        funding[:open_collective_org_source] = open_collective_org.fetch(:source)
      end
      open_collective_files = opencollective_disabled ? opencollective_disabled_files(project_root) : []
      funding[:open_collective_files] = open_collective_files unless open_collective_files.empty?
      facts[:funding] = funding unless funding.empty?
      facts[:ci] = {
        provider: "github_actions",
        default_branch: "main",
        ruby_versions: github_actions_ruby_versions(facts.fetch(:rubygems).fetch(:min_ruby, nil)),
        obsolete_workflows: github_actions_obsolete_workflows(project_root),
        custom_workflows: github_actions_custom_workflows(project_root, opencollective_disabled: opencollective_disabled),
      }
      coverage_config = github_actions_coverage_config(kettle_config)
      facts[:ci][:coverage] = coverage_config unless coverage_config.empty?
      framework_matrix = github_actions_framework_matrix(kettle_config)
      facts[:ci][:framework_matrix] = framework_matrix unless framework_matrix.empty?
      template_facts = {}
      template_preferences = template_source_preferences(project_root, kettle_config, opencollective_disabled: opencollective_disabled)
      template_facts[:source_preferences] = template_preferences unless template_preferences.empty?
      unless template_preferences.empty?
        facts[:license] = license unless license.empty?
        template_tokens = template_tokens(facts, funding)
        template_facts[:tokens] = template_tokens unless template_tokens.empty?
      end
      facts[:templates] = template_facts unless template_facts.empty?
      facts
    end

    def recipe_pack(facts)
      recipes = [
        recipe_entry("readme_metadata", "README.md", "markdown", "supplied_readme_metadata_synchronization", facts: %w[package funding readme]),
        recipe_entry("changelog_unreleased", "CHANGELOG.md", "markdown", "changelog_unreleased_normalization", facts: %w[package changelog]),
        recipe_entry("generated_block_sync", "gemfiles/modular/shunted.gemfile", "text", "supplied_managed_text_block_replacement", facts: %w[package generated_blocks]),
        recipe_entry(
          "github_funding_yml",
          ".github/FUNDING.yml",
          "yaml",
          "supplied_github_funding_yaml_synchronization",
          facts: %w[package funding]
        ),
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
      if facts.dig(:ci, :coverage)
        recipes << recipe_entry(
          "github_actions_coverage_ci",
          ".github/workflows/coverage.yml",
          "yaml",
          "supplied_github_actions_coverage_workflow_synchronization",
          facts: %w[package rubygems ci]
        )
      end
      facts.dig(:ci, :obsolete_workflows).to_a.each do |workflow_path|
        recipes << recipe_entry(
          "github_actions_obsolete_workflow_cleanup_#{workflow_recipe_slug(workflow_path)}",
          workflow_path,
          "file",
          "supplied_obsolete_file_deletion",
          facts: %w[ci]
        )
      end
      facts.dig(:funding, :open_collective_files).to_a.each do |relative_path|
        recipes << recipe_entry(
          "opencollective_disabled_file_cleanup_#{workflow_recipe_slug(relative_path)}",
          relative_path,
          "file",
          "supplied_disabled_opencollective_file_deletion",
          facts: %w[funding]
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
      facts.dig(:templates, :source_preferences).to_a.each do |preference|
        apply_template = preference.fetch(:apply, false)
        recipe = recipe_entry(
          "#{apply_template ? "template_source_application" : "template_source_preference"}_#{workflow_recipe_slug(preference.fetch(:target_path))}",
          preference.fetch(:target_path),
          "file",
          apply_template ? "supplied_template_source_application" : "supplied_template_source_preference",
          facts: %w[templates funding]
        )
        recipe[:template_preference] = preference
        recipe[:template_tokens] = facts.dig(:templates, :tokens) if facts.dig(:templates, :tokens)
        recipes << recipe
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

    def plan_project(project_root, env: ENV)
      facts = discover_facts(project_root, env: env)
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

    def apply_project(project_root, env: ENV)
      report = plan_project(project_root, env: env).merge(mode: "apply")
      report.fetch(:recipe_reports).each do |recipe_report|
        next unless recipe_report[:changed]

        path = File.join(project_root, recipe_report.fetch(:relative_path))
        if recipe_report.dig(:metadata, :delete_file)
          FileUtils.rm_f(path)
        else
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, recipe_report.fetch(:final_content))
        end
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
      when "github_funding_yml"
        synchronize_github_funding_yml(original, facts)
      when "github_actions_ci"
        synchronize_github_actions_ci(original, facts)
      when "github_actions_framework_ci"
        synchronize_github_actions_framework_ci(original, facts)
      when "github_actions_coverage_ci"
        synchronize_github_actions_coverage_ci(original, facts)
      when /\Agithub_actions_obsolete_workflow_cleanup_/
        ""
      when /\Aopencollective_disabled_file_cleanup_/
        ""
      when /\Agithub_actions_workflow_snippets_/
        synchronize_github_actions_workflow_snippets(original)
      when /\Atemplate_source_preference_/
        original
      when /\Atemplate_source_application_/
        apply_template_source(project_root, recipe)
      when "rakefile_scaffold_cleanup"
        deletion.fetch(:content)
      else
        original
      end

      template_content = recipe_template_content(project_root, recipe)
      request = content_recipe_execution_request(
        recipe_name: recipe.fetch(:primitive),
        recipe_version: "1",
        relative_path: relative_path,
        provider_family: recipe.fetch(:provider_family),
        provider_backend: recipe[:provider_backend],
        template_content: template_content,
        destination_content: original,
        steps: [content_recipe_step(recipe)],
        runtime_context: recipe_runtime_context(recipe, facts, deletion),
        metadata: { packaging_recipe: recipe.fetch(:name), project_root: project_root.to_s },
      )
      changed = delete_file_recipe?(recipe) || final != original
      step_report = content_recipe_step_report(recipe: recipe, request: request, original: original, final: final, changed: changed, deletion: deletion)
      report = content_recipe_execution_report(
        request: request,
        final_content: final,
        changed: changed,
        step_reports: [step_report],
        diagnostics: [],
        metadata: recipe_report_metadata(recipe),
      )

      {
        recipe_name: recipe.fetch(:name),
        relative_path: relative_path,
        changed: changed,
        request_envelope: content_recipe_execution_request_envelope(request),
        report_envelope: content_recipe_execution_report_envelope(report),
        final_content: final,
        metadata: recipe_report_metadata(recipe),
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

    def recipe_template_content(project_root, recipe)
      return "" unless %w[supplied_template_source_preference supplied_template_source_application].include?(recipe.fetch(:primitive))

      path = File.join(project_root, recipe.fetch(:template_preference).fetch(:selected_source))
      File.read(path)
    end

    def apply_template_source(project_root, recipe)
      resolve_template_tokens(recipe_template_content(project_root, recipe), recipe.fetch(:template_tokens, {}))
    end

    def recipe_report_metadata(recipe)
      metadata = { packaging_recipe: recipe.fetch(:name) }
      metadata[:delete_file] = true if delete_file_recipe?(recipe)
      metadata[:template_source_preference] = deep_dup(recipe[:template_preference]) if recipe[:template_preference]
      metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      metadata
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
      context[:template_source_preference] = deep_dup(recipe[:template_preference]) if recipe[:template_preference]
      context[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      context
    end

    def step_report_metadata(recipe, deletion)
      metadata = { target_path: recipe.fetch(:target_path) }
      if recipe.fetch(:primitive) == "supplied_obsolete_file_deletion"
        metadata.merge!(
          policy_kind: "delete_obsolete_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path),
        )
      end
      if recipe.fetch(:primitive) == "supplied_disabled_opencollective_file_deletion"
        metadata.merge!(
          policy_kind: "delete_disabled_opencollective_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path),
        )
      end
      if recipe.fetch(:primitive) == "supplied_template_source_preference"
        metadata.merge!(
          policy_kind: "select_template_source",
          operation: "select",
          template_source_preference: deep_dup(recipe.fetch(:template_preference)),
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
      if recipe.fetch(:primitive) == "supplied_template_source_application"
        metadata.merge!(
          policy_kind: "apply_template_source",
          operation: "replace",
          template_source_preference: deep_dup(recipe.fetch(:template_preference)),
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
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

    def funding_urls(project_root, gemspec_source, package_name, opencollective_disabled: false, open_collective_org: nil)
      urls = [extract_metadata_value(gemspec_source, "funding_uri")]
      path = File.join(project_root, ".github", "FUNDING.yml")
      urls.concat(github_funding_urls(path, opencollective_disabled: opencollective_disabled)) if File.exist?(path)
      urls << github_funding_platform_urls("open_collective", [open_collective_org]).first unless opencollective_disabled
      urls << github_funding_platform_urls("tidelift", ["rubygems/#{package_name}"]).first

      urls.compact.uniq.sort
    end

    def github_funding_urls(path, opencollective_disabled: false)
      funding = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      return [] unless funding.is_a?(Hash)

      funding.flat_map do |platform, value|
        next [] if opencollective_disabled && platform.to_s == "open_collective"

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

    def github_actions_custom_workflows(project_root, opencollective_disabled: false)
      workflow_root = File.join(project_root, ".github", "workflows")
      return [] unless Dir.exist?(workflow_root)

      Dir.glob(File.join(workflow_root, "*.{yml,yaml}")).filter_map do |path|
        relative_path = path.delete_prefix("#{project_root}/")
        next if opencollective_disabled && opencollective_disabled_file?(relative_path)
        next if generated_or_obsolete_github_workflow?(relative_path)

        relative_path
      end.sort
    end

    def github_actions_obsolete_workflows(project_root)
      workflow_root = File.join(project_root, ".github", "workflows")
      OBSOLETE_GITHUB_WORKFLOWS.filter_map do |workflow|
        relative_path = ".github/workflows/#{workflow}"
        path = File.join(workflow_root, workflow)
        relative_path if File.exist?(path)
      end.sort
    end

    def generated_or_obsolete_github_workflow?(relative_path)
      return true if %w[.github/workflows/ci.yml .github/workflows/coverage.yml .github/workflows/framework-ci.yml].include?(relative_path)

      OBSOLETE_GITHUB_WORKFLOWS.include?(File.basename(relative_path))
    end

    def opencollective_disabled_files(project_root)
      OPENCOLLECTIVE_DISABLED_FILES.select do |relative_path|
        File.exist?(File.join(project_root, relative_path))
      end
    end

    def opencollective_disabled_file?(relative_path)
      OPENCOLLECTIVE_DISABLED_FILES.include?(relative_path.to_s)
    end

    def delete_file_recipe?(recipe)
      FILE_DELETION_PRIMITIVES.include?(recipe.fetch(:primitive))
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

    def opencollective_disabled?(config, env: ENV)
      opencollective_policy(config, env).fetch(:disabled)
    end

    def opencollective_policy(config, env)
      funding = config["funding"]
      if funding.is_a?(Hash) && funding.key?("open_collective")
        config_value = funding["open_collective"]
        return {
          disabled: falsey_config?(config_value),
          source: "config.funding.open_collective",
          value: config_value.to_s,
        }
      end

      env_falsey = opencollective_falsey_env(env)
      return { disabled: true, source: "env.#{env_falsey.fetch(:key)}", value: env_falsey.fetch(:value).to_s } if env_falsey

      { disabled: false }
    end

    def opencollective_falsey_env(env)
      %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG].each do |key|
        value = env[key]
        return { key: key, value: value } if falsey_config?(value)
      end
      nil
    end

    def opencollective_org(project_root, env, opencollective_disabled: false)
      return nil if opencollective_disabled

      env_org = opencollective_org_env(env)
      return env_org if env_org

      opencollective_org_file(project_root)
    end

    def opencollective_org_env(env)
      %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG].each do |key|
        value = env[key].to_s.strip
        next if value.empty? || falsey_config?(value)

        return { org: value, source: "env.#{key}" }
      end
      nil
    end

    def opencollective_org_file(project_root)
      path = File.join(project_root, ".opencollective.yml")
      return nil unless File.exist?(path)

      config = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      return nil unless config.is_a?(Hash)

      org = config.fetch("collective", config["org"]).to_s.strip
      return nil if org.empty?

      { org: org, source: ".opencollective.yml" }
    end

    def template_tokens(facts, funding)
      package = facts.fetch(:package)
      rubygems = facts.fetch(:rubygems)
      tokens = {
        "KJ|GEM_NAME" => package.fetch(:name).to_s,
        "KJ|GEM_NAME_PATH" => package.fetch(:name).to_s.tr("-", "/"),
        "KJ|NAMESPACE" => rubygems.fetch(:namespace).to_s,
        "KJ|MIN_RUBY" => minimum_ruby_token(rubygems[:min_ruby]),
      }.merge(
        author_template_tokens(facts.fetch(:author, {}))
      ).merge(
        forge_template_tokens(facts.fetch(:forge, {}))
      ).merge(
        funding_template_tokens(funding)
      ).merge(
        social_template_tokens(facts.fetch(:social, {}))
      ).merge(
        license_template_tokens(facts.fetch(:license, {}))
      )
      org = funding[:open_collective_org].to_s
      tokens["KJ|OPENCOLLECTIVE_ORG"] = org unless org.empty?

      tokens.reject { |_, value| value.empty? }
    end

    def minimum_ruby_token(requirement)
      requirement.to_s[/\d+(?:\.\d+){1,2}/].to_s
    end

    def author_facts(gemspec_source, config, env)
      token_config = token_config_values(config)
      author_config = token_config["author"].is_a?(Hash) ? token_config["author"] : {}
      derived_name = extract_gemspec_array(gemspec_source, "spec.authors").first
      derived_email = extract_gemspec_array(gemspec_source, "spec.email").first
      name = preferred_template_token_value(derived_name, author_config["name"], env, "KJ_AUTHOR_NAME").to_s
      email = preferred_template_token_value(derived_email, author_config["email"], env, "KJ_AUTHOR_EMAIL").to_s
      given_names = preferred_template_token_value(author_given_names(name), author_config["given_names"], env, "KJ_AUTHOR_GIVEN_NAMES")
      family_names = preferred_template_token_value(author_family_names(name), author_config["family_names"], env, "KJ_AUTHOR_FAMILY_NAMES")
      domain = preferred_template_token_value(email.split("@", 2)[1], author_config["domain"], env, "KJ_AUTHOR_DOMAIN")
      orcid = preferred_template_token_value(nil, author_config["orcid"], env, "KJ_AUTHOR_ORCID")
      compact_hash(
        name: name,
        given_names: given_names.to_s,
        family_names: family_names.to_s,
        email: email,
        domain: domain.to_s,
        orcid: orcid.to_s
      )
    end

    def token_config_values(config)
      raw = config.is_a?(Hash) ? config["tokens"] : nil
      raw.is_a?(Hash) ? raw : {}
    end

    def preferred_template_token_value(derived_value, config_value, env, env_key)
      env_clean = env[env_key].to_s.strip
      return env_clean if present_template_token_value?(env_clean)

      config_clean = config_value.to_s.strip
      return config_clean if present_template_token_value?(config_clean)
      return unless present_template_token_value?(derived_value)

      derived_value.to_s.strip
    end

    def present_template_token_value?(value)
      clean = value.to_s.strip
      !clean.empty? && !token_placeholder?(clean)
    end

    def token_placeholder?(value)
      value.to_s.strip.match?(%r{\A\{KJ\|[A-Z][A-Z0-9_:]*\}\z})
    end

    def author_template_tokens(author)
      {
        "KJ|AUTHOR:NAME" => author[:name].to_s,
        "KJ|AUTHOR:GIVEN_NAMES" => author[:given_names].to_s,
        "KJ|AUTHOR:FAMILY_NAMES" => author[:family_names].to_s,
        "KJ|AUTHOR:EMAIL" => author[:email].to_s,
        "KJ|AUTHOR:DOMAIN" => author[:domain].to_s,
        "KJ|AUTHOR:ORCID" => author[:orcid].to_s,
      }
    end

    def forge_facts(config, env)
      token_config = token_config_values(config)
      forge_config = token_config["forge"].is_a?(Hash) ? token_config["forge"] : {}
      compact_hash(
        gh_user: forge_user_value(forge_config, env, :gh_user).to_s,
        gl_user: forge_user_value(forge_config, env, :gl_user).to_s,
        cb_user: forge_user_value(forge_config, env, :cb_user).to_s,
        sh_user: forge_user_value(forge_config, env, :sh_user).to_s
      )
    end

    def forge_user_value(forge_config, env, key)
      preferred_template_token_value(nil, forge_config[key.to_s], env, FORGE_USER_ENV_KEYS.fetch(key))
    end

    def forge_template_tokens(forge)
      {
        "KJ|GH:USER" => forge[:gh_user].to_s,
        "KJ|GL:USER" => forge[:gl_user].to_s,
        "KJ|CB:USER" => forge[:cb_user].to_s,
        "KJ|SH:USER" => forge[:sh_user].to_s,
      }
    end

    def funding_platform_token_facts(config, env)
      token_config = token_config_values(config)
      funding_config = token_config["funding"].is_a?(Hash) ? token_config["funding"] : {}
      compact_hash(
        patreon: funding_platform_token_value(funding_config, env, :patreon).to_s,
        kofi: funding_platform_token_value(funding_config, env, :kofi).to_s,
        paypal: funding_platform_token_value(funding_config, env, :paypal).to_s,
        buymeacoffee: funding_platform_token_value(funding_config, env, :buymeacoffee).to_s,
        polar: funding_platform_token_value(funding_config, env, :polar).to_s,
        liberapay: funding_platform_token_value(funding_config, env, :liberapay).to_s,
        issuehunt: funding_platform_token_value(funding_config, env, :issuehunt).to_s
      )
    end

    def funding_platform_token_value(funding_config, env, key)
      preferred_template_token_value(nil, funding_config[key.to_s], env, FUNDING_TOKEN_ENV_KEYS.fetch(key))
    end

    def funding_template_tokens(funding)
      platform_tokens = funding.fetch(:platform_tokens, {})
      {
        "KJ|FUNDING:PATREON" => platform_tokens[:patreon].to_s,
        "KJ|FUNDING:KOFI" => platform_tokens[:kofi].to_s,
        "KJ|FUNDING:PAYPAL" => platform_tokens[:paypal].to_s,
        "KJ|FUNDING:BUYMEACOFFEE" => platform_tokens[:buymeacoffee].to_s,
        "KJ|FUNDING:POLAR" => platform_tokens[:polar].to_s,
        "KJ|FUNDING:LIBERAPAY" => platform_tokens[:liberapay].to_s,
        "KJ|FUNDING:ISSUEHUNT" => platform_tokens[:issuehunt].to_s,
      }
    end

    def social_facts(config, env)
      token_config = token_config_values(config)
      social_config = token_config["social"].is_a?(Hash) ? token_config["social"] : {}
      compact_hash(
        mastodon: social_token_value(social_config, env, :mastodon).to_s,
        bluesky: social_token_value(social_config, env, :bluesky).to_s,
        linktree: social_token_value(social_config, env, :linktree).to_s,
        devto: social_token_value(social_config, env, :devto).to_s
      )
    end

    def social_token_value(social_config, env, key)
      preferred_template_token_value(nil, social_config[key.to_s], env, SOCIAL_TOKEN_ENV_KEYS.fetch(key))
    end

    def social_template_tokens(social)
      {
        "KJ|SOCIAL:MASTODON" => social[:mastodon].to_s,
        "KJ|SOCIAL:BLUESKY" => social[:bluesky].to_s,
        "KJ|SOCIAL:LINKTREE" => social[:linktree].to_s,
        "KJ|SOCIAL:DEVTO" => social[:devto].to_s,
      }
    end

    def license_facts(config, gemspec_licenses, author_email: nil)
      licenses = resolved_licenses(config, gemspec_licenses)
      primary = licenses.first
      compat_category = license_compat_category(licenses)
      compact_hash(
        spdx: licenses,
        expression: licenses.join(" OR "),
        primary_spdx: primary,
        license_md_content: license_md_content(licenses, author_email: author_email),
        readme_license_intro: readme_license_intro(licenses, author_email: author_email),
        readme_license_badge: license_badge(primary),
        readme_license_compat_badge: license_compat_badge(compat_category),
        readme_license_refs: readme_license_refs(primary, compat_category),
        copyright_prefix: polyform_licenses?(licenses) ? "Required Notice: " : ""
      )
    end

    def resolved_licenses(config, gemspec_licenses)
      config_licenses = config.is_a?(Hash) ? config["licenses"] : nil
      licenses = Array(config_licenses).map { |license| license.to_s.strip }.reject(&:empty?)
      return licenses unless licenses.empty?

      licenses = Array(gemspec_licenses).map { |license| license.to_s.strip }.reject(&:empty?)
      licenses.empty? ? ["MIT"] : licenses
    end

    def license_template_tokens(license)
      {
        "KJ|LICENSE_MD_CONTENT" => license[:license_md_content].to_s,
        "KJ|README:LICENSE_INTRO" => license[:readme_license_intro].to_s,
        "KJ|LICENSE:PRIMARY_SPDX" => license[:primary_spdx].to_s,
        "KJ|README:LICENSE_BADGE" => license[:readme_license_badge].to_s,
        "KJ|README:LICENSE_COMPAT_BADGE" => license[:readme_license_compat_badge].to_s,
        "KJ|README:LICENSE_REFS" => license[:readme_license_refs].to_s,
        "KJ|COPYRIGHT_PREFIX" => license[:copyright_prefix].to_s,
      }
    end

    def license_md_content(licenses, author_email: nil)
      content = <<~MARKDOWN.chomp
        # License

        This project is made available under the following license#{"s" if licenses.size > 1}.
        Choose the option that best fits your use case:

        #{licenses.map { |license| "- #{license_link(license)}" }.join("\n")}
      MARKDOWN
      guide_table = license_use_case_guide_table(licenses, author_email: author_email)
      content += "\n\n## Use-case guide\n\n#{guide_table}" if guide_table
      content += "\n\n#{license_contact_line(author_email, context: :license_md)}" if non_mit_licenses?(licenses)
      content
    end

    def readme_license_intro(licenses, author_email: nil)
      return mit_readme_license_intro if licenses == ["MIT"]

      intro = "The gem is available under the following license#{"s" if licenses.size > 1}: " \
        "#{licenses.map { |license| license_link(license) }.join(", ")}.\n" \
        "See [LICENSE.md][#{paperclip_ref(:license)}] for details."
      intro += "\n\n#{license_contact_line(author_email, context: :readme)}" if non_mit_licenses?(licenses)
      guide_table = license_use_case_guide_table(licenses, author_email: author_email)
      intro += "\n\n### License use-case guide\n\n#{guide_table}" if guide_table
      intro
    end

    def mit_readme_license_intro
      "The gem is available as open source under the terms of\n" \
        "the #{license_link("MIT")} #{license_badge("MIT")}."
    end

    def license_contact_line(author_email, context:)
      if author_email.to_s.empty?
        return "If none of the above licenses fit your use case, please contact the project maintainer to discuss a custom commercial license." if context == :license_md

        "If none of the available licenses suit your use case, please contact the project maintainer to discuss a custom commercial license."
      elsif context == :license_md
        "If none of the above licenses fit your use case, please [contact us](mailto:#{author_email}) to discuss a custom commercial license."
      else
        "If none of the available licenses suit your use case, please [contact us](mailto:#{author_email}) to discuss a custom commercial license."
      end
    end

    def readme_license_refs(primary, compat_category)
      [
        "[#{paperclip_ref(:copyright_notice_explainer)}]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year",
        "[#{paperclip_ref(:license)}]: LICENSE.md",
        "[#{paperclip_ref(:license_ref)}]: #{license_badge_ref(primary)}",
        "[#{paperclip_ref(:license_img)}]: #{license_badge_img(primary)}",
        "[#{paperclip_ref(:license_compat)}]: #{license_compat_ref(compat_category)}",
        "[#{paperclip_ref(:license_compat_img)}]: #{license_compat_img(compat_category)}",
      ].join("\n")
    end

    def spdx_basename(spdx_id)
      spdx_id.to_s.sub(/\ALicenseRef-/, "")
    end

    def license_link(spdx_id)
      base = spdx_basename(spdx_id)
      "[#{base}](#{base}.md)"
    end

    def license_badge(spdx_id)
      base = spdx_basename(spdx_id)
      "[![License: #{base}][#{paperclip_ref(:license_img)}]][#{paperclip_ref(:license_ref)}]"
    end

    def license_badge_ref(spdx_id)
      "#{spdx_basename(spdx_id)}.md"
    end

    def license_badge_img(spdx_id)
      base = spdx_basename(spdx_id).gsub("-", "--").gsub("_", "__").tr(" ", "_")
      "https://img.shields.io/badge/License-#{base}-259D6C.svg"
    end

    def license_compat_category(licenses)
      categories = Array(licenses).filter_map { |license| APACHE_LICENSE_COMPAT_CATEGORIES[license.to_s] }.uniq
      return :a if categories.include?(:a)
      return :b if categories.include?(:b)
      return :x if categories.any? && categories.all?(:x)

      :unknown
    end

    def license_compat_badge(category)
      data = APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category)
      "[![#{data.fetch(:alt)}][#{paperclip_ref(:license_compat_img)}]][#{paperclip_ref(:license_compat)}]"
    end

    def license_compat_ref(category)
      APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category).fetch(:ref)
    end

    def license_compat_img(category)
      data = APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category)
      "https://img.shields.io/badge/#{data.fetch(:label)}-#{data.fetch(:message)}-#{data.fetch(:color)}.svg?style=flat&logo=Apache"
    end

    def polyform_licenses?(licenses)
      licenses.any? { |license| license.to_s.start_with?("PolyForm-") }
    end

    def non_mit_licenses?(licenses)
      licenses.any? { |license| license != "MIT" }
    end

    def license_use_case_guide_table(licenses, author_email: nil)
      has_floss_oss = licenses.include?("MIT") || licenses.include?("AGPL-3.0-only")
      has_polyform = licenses.include?("PolyForm-Noncommercial-1.0.0") || licenses.include?("PolyForm-Small-Business-1.0.0")
      has_big_time = licenses.include?("LicenseRef-Big-Time-Public-License")
      return unless has_floss_oss && has_polyform && has_big_time

      rows = license_use_case_rows(licenses, author_email: author_email)
      return if rows.empty?

      "| Use case | License |\n|---|---|\n" +
        rows.map { |use_case, license| "| #{use_case} | #{license} |" }.join("\n")
    end

    def license_use_case_rows(licenses, author_email: nil)
      rows = []
      rows << ["FLOSS (free and open source)", license_link("MIT")] if licenses.include?("MIT")
      rows << ["Copy-left open source", license_link("AGPL-3.0-only")] if licenses.include?("AGPL-3.0-only")
      noncommercial_links = %w[PolyForm-Noncommercial-1.0.0 PolyForm-Small-Business-1.0.0 LicenseRef-Big-Time-Public-License]
        .select { |license| licenses.include?(license) }
        .map { |license| license_link(license) }
      rows << ["Non-commercial (research, education, personal use)", noncommercial_links.join(" or ")] unless noncommercial_links.empty?
      small_business_links = %w[PolyForm-Small-Business-1.0.0 LicenseRef-Big-Time-Public-License]
        .select { |license| licenses.include?(license) }
        .map { |license| license_link(license) }
      rows << ["Small business commercial", small_business_links.join(" or ")] unless small_business_links.empty?
      rows << ["Larger business commercial", large_business_license_cell(author_email)] if licenses.include?("LicenseRef-Big-Time-Public-License")
      rows
    end

    def large_business_license_cell(author_email)
      cell = license_link("LicenseRef-Big-Time-Public-License")
      if author_email.to_s.empty?
        "#{cell} or contact us for a custom license"
      else
        "#{cell} or [contact us](mailto:#{author_email}) for a custom license"
      end
    end

    def paperclip_ref(name)
      {
        copyright_notice_explainer: "\u{1F4C4}copyright-notice-explainer",
        license: "\u{1F4C4}license",
        license_ref: "\u{1F4C4}license-ref",
        license_img: "\u{1F4C4}license-img",
        license_compat: "\u{1F4C4}license-compat",
        license_compat_img: "\u{1F4C4}license-compat-img",
      }.fetch(name)
    end

    def author_given_names(name)
      parts = name.to_s.strip.split(/\s+/)
      return "" if parts.size < 2

      parts[0...-1].join(" ")
    end

    def author_family_names(name)
      parts = name.to_s.strip.split(/\s+/)
      return "" if parts.size < 2

      parts[-1]
    end

    def resolve_template_tokens(content, tokens)
      resolver = Token::Resolver::Resolve.new(on_missing: :keep)
      document = Token::Resolver::Document.new(content.to_s, config: TEMPLATE_TOKEN_CONFIG)
      resolved = resolver.resolve(document, stringify_template_tokens(tokens))
      unresolved = Token::Resolver::Document.new(resolved, config: TEMPLATE_TOKEN_CONFIG).token_keys.grep(/\AKJ\|/).sort
      return resolved if unresolved.empty?

      raise ArgumentError, "unresolved kettle-jem template tokens: #{unresolved.map { |token| "{#{token}}" }.join(", ")}"
    end

    def stringify_template_tokens(tokens)
      tokens.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end

    def falsey_config?(value)
      %w[false no 0].include?(value.to_s.strip.downcase)
    end

    def template_source_preferences(project_root, config, opencollective_disabled: false)
      templates = config["templates"]
      return [] unless templates.is_a?(Hash)

      root = templates.fetch("root", "template").to_s
      entries = templates["entries"]
      return [] unless entries.is_a?(Array)

      apply_templates = templates["apply"] == true
      entries.filter_map do |entry|
        template_source_preference(project_root, root, entry, opencollective_disabled: opencollective_disabled, apply_templates: apply_templates)
      end
    end

    def template_source_preference(project_root, template_root, entry, opencollective_disabled: false, apply_templates: false)
      source_path, target_path = template_entry_paths(entry)
      return nil if source_path.to_s.empty? || target_path.to_s.empty?

      selected_source = preferred_template_source(project_root, File.join(template_root, source_path), opencollective_disabled: opencollective_disabled)
      return nil unless selected_source

      {
        target_path: target_path,
        configured_source: source_path,
        selected_source: selected_source,
        selection_reason: template_source_selection_reason(source_path, selected_source),
        apply: template_entry_apply?(entry, apply_templates),
      }
    end

    def template_entry_paths(entry)
      if entry.is_a?(Hash)
        source_path = entry.fetch("source", entry["target"]).to_s
        target_path = entry.fetch("target", source_path.sub(/\.example\z/, "")).to_s
        [source_path, target_path]
      else
        source_path = entry.to_s
        [source_path, source_path.sub(/\.example\z/, "")]
      end
    end

    def template_entry_apply?(entry, apply_templates)
      return entry["apply"] == true if entry.is_a?(Hash) && entry.key?("apply")

      apply_templates
    end

    def preferred_template_source(project_root, configured_source, opencollective_disabled: false)
      base = configured_source.sub(/\.example\z/, "")
      candidates = []
      candidates << "#{base}.no-osc.example" if opencollective_disabled
      candidates << "#{base}.example"
      candidates << configured_source
      candidates.find { |relative_path| File.exist?(File.join(project_root, relative_path)) }
    end

    def template_source_selection_reason(configured_source, selected_source)
      if selected_source.end_with?(".no-osc.example")
        "opencollective_disabled_no_osc_variant"
      elsif selected_source.end_with?(".example")
        "default_example_variant"
      elsif selected_source == configured_source
        "configured_source"
      else
        "fallback_source"
      end
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

    def github_actions_coverage_config(config)
      workflows = config["workflows"]
      return {} unless workflows.is_a?(Hash)

      raw = workflows["coverage"]
      enabled = raw == true || (raw.is_a?(Hash) && raw.fetch("enabled", false) == true)
      return {} unless enabled

      raw = {} unless raw.is_a?(Hash)
      {
        enabled: true,
        command: raw.fetch("command", "rake test").to_s,
        appraisal: raw.fetch("appraisal", "coverage").to_s,
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

    def synchronize_github_funding_yml(content, facts)
      funding = YAML.safe_load(content.to_s, permitted_classes: [], aliases: false) || {}
      funding = {} unless funding.is_a?(Hash)
      funding = funding.each_with_object({}) do |(key, value), memo|
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        memo[key.to_s] = value
      end
      funding.delete("open_collective") if facts.fetch(:funding, {})[:open_collective_disabled]
      funding["tidelift"] ||= "rubygems/#{facts.fetch(:package).fetch(:name)}"
      YAML.dump(funding).sub(/\A---\n?/, "")
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

    def synchronize_github_actions_coverage_ci(_content, facts)
      ci = facts.fetch(:ci)
      coverage = ci.fetch(:coverage)
      <<~YAML
        name: Test Coverage

        permissions:
          contents: read
          pull-requests: write
          id-token: write

        env:
          K_SOUP_COV_MIN_BRANCH: 100
          K_SOUP_COV_MIN_LINE: 100
          K_SOUP_COV_MIN_HARD: true
          K_SOUP_COV_FORMATTERS: "xml,rcov,lcov,tty"
          K_SOUP_COV_DO: true
          K_SOUP_COV_MULTI_FORMATTERS: true
          K_SOUP_COV_COMMAND_NAME: "Test Coverage"

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
          coverage:
            if: "!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')"
            name: Code Coverage on ${{ matrix.ruby }}@current
            runs-on: ubuntu-latest
            continue-on-error: ${{ matrix.experimental || endsWith(matrix.ruby, 'head') }}
            env:
              BUNDLE_GEMFILE: ${{ github.workspace }}/${{ matrix.gemfile }}.gemfile
            strategy:
              fail-fast: false
              matrix:
                include:
                  - ruby: "ruby"
                    appraisal: "#{coverage.fetch(:appraisal)}"
                    exec_cmd: "#{coverage.fetch(:command)}"
                    gemfile: "Appraisal.root"
                    rubygems: latest
                    bundler: latest

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

              - name: "[Attempt 1] Appraisal for ${{ matrix.ruby }}@${{ matrix.appraisal }}"
                id: bundleAppraisalAttempt1
                run: bundle exec appraisal ${{ matrix.appraisal }} install
                continue-on-error: true

              - name: "[Attempt 2] Appraisal for ${{ matrix.ruby }}@${{ matrix.appraisal }}"
                id: bundleAppraisalAttempt2
                if: ${{ steps.bundleAppraisalAttempt1.outcome == 'failure' }}
                run: bundle exec appraisal ${{ matrix.appraisal }} install

              - name: Tests for ${{ matrix.ruby }}@current via ${{ matrix.exec_cmd }}
                run: bundle exec appraisal ${{ matrix.appraisal }} bundle exec ${{ matrix.exec_cmd }}
        #{github_actions_coverage_steps}
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
