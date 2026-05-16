# frozen_string_literal: true

require "fileutils"
require "find"
require "English"
require "digest"
require "json"
require "net/http"
require "open3"
require "rbconfig"
require "set"
require "time"
require "uri"
require "ruby/merge"
require "token/resolver"
require "toml-merge"
require "yaml"
require "yaml/merge"
require "ast/merge"
require_relative "jem/version"

module Kettle
  module Jem
    class Error < StandardError; end

    PACKAGE_NAME = "kettle-jem"
    CONTENT_RECIPE_TRANSPORT_VERSION = Ast::Merge::STRUCTURED_EDIT_TRANSPORT_VERSION
    MANAGED_BLOCK_OPEN = "# <<kettle-jem:generated>> do not edit below this line"
    MANAGED_BLOCK_CLOSE = "# <</kettle-jem:generated>>"
    OBSOLETE_GITHUB_WORKFLOWS = %w[ancient.yml legacy.yml supported.yml unsupported.yml main.yml hoary.yml].freeze
    OPENCOLLECTIVE_DISABLED_FILES = %w[.opencollective.yml .github/workflows/opencollective.yml].freeze
    FILE_DELETION_PRIMITIVES = %w[
      supplied_obsolete_file_deletion
      supplied_disabled_opencollective_file_deletion
      supplied_legacy_destination_file_deletion
    ].freeze
    PHASE_ORDER = %i[
      config_sync
      dev_container
      github_workflows
      quality_config
      modular_gemfiles
      spec_helper
      environment_templates
      remaining_files
      git_hooks
      license_files
      duplicate_check
    ].freeze
    PACKAGED_TEMPLATE_ROOT = File.expand_path("jem/templates", __dir__)
    COPY_ONLY_WHEN_MISSING_TEMPLATE_PATHS = %w[REEK bin/setup].freeze
    LEGACY_DESTINATION_PATHS = {
      ".github/copilot_instructions.md" => ".github/COPILOT_INSTRUCTIONS.md",
    }.freeze
    SUPPORTED_TEMPLATE_STRATEGIES = %i[merge accept_template keep_destination raw_copy].freeze
    SUPPORTED_TEMPLATE_FILE_TYPES = %i[ruby gemfile appraisals gemspec rakefile yaml toml markdown text].freeze
    SUPPORTED_RUBY_METHOD_MOVE_POLICIES = %w[destination_order].freeze
    RUBY_TEMPLATE_BASENAMES = %w[Gemfile Rakefile Appraisals Appraisal.root.gemfile .simplecov].freeze
    RUBY_TEMPLATE_SUFFIXES = %w[.gemspec .gemfile].freeze
    RUBY_TEMPLATE_EXTENSIONS = %w[.rb .rake].freeze
    TEMPLATE_TOKEN_CONFIG = Token::Resolver::Config.new(separators: ["|", ":"]).freeze
    EMPTY_TEMPLATE_TOKENS = %w[KJ|COPYRIGHT_PREFIX KJ|MIN_DIVERGENCE_THRESHOLD].freeze
    COPYRIGHT_NAME_RE = /\ACopyright \(c\) [\d,\s\-]+ (.+)\z/
    BOT_EMAIL_PATTERN = /\A\d+\+[^@]+\[bot\]@/i
    BOT_NAME_SUFFIX = /\[bot\]\z/i
    NOT_COMMITTED_EMAIL = "not.committed.yet"
    LOGOS_GALTZO_BASE_URL = "https://logos.galtzo.com/assets/images"
    README_TOP_LOGO_MODE_DEFAULT = "org_and_project"
    README_TOP_LOGO_MODES = %w[org project org_and_project].freeze
    README_TOP_LOGO_TYPES = %w[language org project affiliated_project].freeze
    APPRAISAL_NAME_PREFIX = "kja"
    APPRAISAL_GEM_ABBREVIATIONS = {
      "activerecord" => "ar",
      "actionmailer" => "am",
      "actionpack" => "ap",
      "activesupport" => "as",
      "activejob" => "aj",
      "actioncable" => "ac",
      "actionview" => "av",
      "activestorage" => "ast",
      "actionmailbox" => "amb",
      "actiontext" => "at",
      "omniauth" => "oa",
      "mongoid" => "mo",
      "sequel" => "sq",
      "couch_potato" => "cp",
      "rom" => "rom",
      "rom-sql" => "rsql",
    }.freeze
    APPRAISAL_WORKFLOW_LIFECYCLE_RANGES = {
      "current" => { min: Gem::Version.new("3.4"), max: Gem::Version.new("3.99") },
      "supported" => { min: Gem::Version.new("3.2"), max: Gem::Version.new("3.3") },
      "legacy" => { min: Gem::Version.new("3.0"), max: Gem::Version.new("3.1") },
      "unsupported" => { min: Gem::Version.new("2.6"), max: Gem::Version.new("2.7") },
      "ancient" => { min: Gem::Version.new("2.3"), max: Gem::Version.new("2.5") },
    }.freeze
    APPRAISAL_ALWAYS_EXCLUDED_GEMS = %w[version_gem].freeze
    APPRAISAL_VERSION_SELECTION_MODES = %w[major minor patch minor-minmax semver].freeze
    APPRAISAL_MINIMUM_RUBY_FLOOR = Gem::Version.new("2.3")
    APPRAISAL_DEFAULT_FRESHNESS_TTL = 604_800
    DECISION_ACTIONS = %w[create merge replace keep delete skip].freeze
    DECISION_SEVERITIES = %w[advisory warning fatal].freeze

    DecisionEvaluation = Struct.new(
      :id,
      :category,
      :file,
      :default_action,
      :selected_action,
      :source,
      :severity,
      :blocking,
      :diagnostics,
      keyword_init: true
    ) do
      def to_h
        {
          id: id,
          category: category,
          file: file,
          default_action: default_action,
          selected_action: selected_action,
          source: source,
          severity: severity,
          blocking: blocking,
          diagnostics: diagnostics,
        }.compact
      end
    end

    class DecisionPolicy
      TRUE_VALUES = %w[1 true y yes on].freeze
      FALSE_VALUES = %w[0 false n no off].freeze

      attr_reader :mode, :failure_mode, :require_clean, :input_source

      def self.from_env(env = {}, **options)
        env_hash = env || {}
        option_hash = symbolize_keys(options)
        interactive = option_hash.key?(:interactive) ? option_hash[:interactive] : truthy?(env_hash["interactive"])
        force = option_hash.key?(:force) ? option_hash[:force] : value_to_boolean(env_hash["force"])
        accept = option_hash.key?(:accept) ? option_hash[:accept] : value_to_boolean(env_hash["accept"])
        interactive = false if accept == true || force == true
        interactive = true if force == false && accept != true && !option_hash.key?(:interactive)
        new(
          mode: interactive ? :interactive : :accept,
          failure_mode: option_hash.fetch(:failure_mode, env_hash["FAILURE_MODE"] || env_hash["failure_mode"] || "error"),
          require_clean: option_hash.fetch(:require_clean, value_to_boolean(env_hash["KETTLE_JEM_REQUIRE_CLEAN"])),
          input_source: option_hash.fetch(:input_source, "default")
        )
      end

      def self.symbolize_keys(hash)
        hash.each_with_object({}) { |(key, value), acc| acc[key.to_sym] = value }
      end

      def self.truthy?(value)
        TRUE_VALUES.include?(value.to_s.strip.downcase)
      end

      def self.falsey?(value)
        FALSE_VALUES.include?(value.to_s.strip.downcase)
      end

      def self.value_to_boolean(value)
        return true if value == true
        return false if value == false
        return true if truthy?(value)
        return false if falsey?(value)

        nil
      end

      def initialize(mode: :accept, failure_mode: "error", require_clean: nil, input_source: "default")
        @mode = normalize_mode(mode)
        @failure_mode = failure_mode.to_s.empty? ? "error" : failure_mode.to_s
        @require_clean = require_clean
        @input_source = input_source.to_s
      end

      def accept?
        mode == :accept
      end

      def interactive?
        mode == :interactive
      end

      def non_interactive?
        !interactive?
      end

      def resolve(id:, category:, default_action:, file: nil, severity: :advisory, diagnostics: [])
        action = normalize_action(default_action)
        severity_value = normalize_severity(severity)
        raise Error, "No safe default decision for #{id}" if action.nil? && severity_value == "fatal"

        DecisionEvaluation.new(
          id: id.to_s,
          category: category.to_s,
          file: file&.to_s,
          default_action: action,
          selected_action: action,
          source: "default",
          severity: severity_value,
          blocking: severity_value == "fatal",
          diagnostics: Array(diagnostics).compact.map(&:to_s)
        )
      end

      def to_h
        {
          mode: mode.to_s,
          non_interactive: non_interactive?,
          accept: accept?,
          interactive: interactive?,
          failure_mode: failure_mode,
          require_clean: require_clean,
          input_source: input_source,
        }.compact
      end

      private

      def normalize_mode(value)
        normalized = value.to_s.strip.downcase.tr("-", "_")
        return :interactive if normalized == "interactive"
        return :accept if normalized.empty? || %w[accept force non_interactive default].include?(normalized)

        raise ArgumentError, "Unsupported Kettle/Jem decision mode #{value.inspect}"
      end

      def normalize_action(value)
        return if value.nil?

        action = value.to_s.strip
        raise ArgumentError, "Unsupported Kettle/Jem decision action #{value.inspect}" unless DECISION_ACTIONS.include?(action)

        action
      end

      def normalize_severity(value)
        severity_value = value.to_s.strip
        raise ArgumentError, "Unsupported Kettle/Jem decision severity #{value.inspect}" unless DECISION_SEVERITIES.include?(severity_value)

        severity_value
      end
    end

    class RubyGemsResolver
      RUBYGEMS_V1_API_BASE = "https://rubygems.org/api/v1"
      RUBYGEMS_V2_API_BASE = "https://rubygems.org/api/v2/rubygems"

      attr_reader :cache

      def initialize(cache: {}, http_get: nil, v1_api_base: RUBYGEMS_V1_API_BASE, v2_api_base: RUBYGEMS_V2_API_BASE)
        @cache = cache
        @http_get = http_get || ->(uri) { Net::HTTP.get_response(uri) }
        @v1_api_base = v1_api_base.to_s.delete_suffix("/")
        @v2_api_base = v2_api_base.to_s.delete_suffix("/")
      end

      def versions(gem_name, include_prerelease: false, requirements: nil)
        requirement = normalize_requirements(requirements)
        fetch_versions(gem_name).filter_map do |entry|
          number = entry["number"].to_s
          next if number.empty?
          next if !include_prerelease && entry["prerelease"]
          next if requirement && !requirement.satisfied_by?(Gem::Version.new(number))

          {
            number: number,
            ruby_version: entry["ruby_version"],
            created_at: entry["created_at"],
            prerelease: !!entry["prerelease"],
          }
        end.sort_by { |entry| Gem::Version.new(entry.fetch(:number)) }
      end

      def version_info(gem_name, version)
        data = fetch_gem_info(gem_name, version)
        return unless data

        runtime_dependencies = Array(data.dig("dependencies", "runtime")).map do |dependency|
          {
            name: dependency["name"],
            requirements: dependency["requirements"],
          }
        end

        {
          number: data["number"] || version.to_s,
          ruby_version: data["ruby_version"],
          runtime_dependencies: runtime_dependencies,
        }
      end

      def min_ruby_version(gem_name, version)
        entry = fetch_versions(gem_name).find { |candidate| candidate["number"].to_s == version.to_s }
        parse_min_ruby(entry && entry["ruby_version"])
      end

      def minor_versions_by_major(gem_name, requirements: nil)
        versions(gem_name, requirements: requirements).each_with_object({}) do |entry, grouped|
          version = Gem::Version.new(entry.fetch(:number))
          segments = version.segments
          next unless segments[0]

          major = segments[0]
          minor = "#{segments[0]}.#{segments[1] || 0}"
          grouped[major] ||= Set.new
          grouped[major] << minor
        end.sort_by(&:first).map do |major, minors|
          {
            major: major,
            minors: minors.to_a.sort_by { |minor| Gem::Version.new(minor) },
          }
        end
      end

      def fetch_versions(gem_name)
        cache_key = "versions:#{gem_name}"
        return cache.fetch(cache_key) if cache.key?(cache_key)

        uri = URI("#{@v1_api_base}/versions/#{escape_path_component(gem_name)}.json")
        response = @http_get.call(uri)
        raise Error, "RubyGems API error for #{gem_name}: #{response_code(response)}" unless successful_response?(response)

        cache[cache_key] = JSON.parse(response_body(response)).sort_by { |entry| Gem::Version.new(entry.fetch("number")) }
      end

      def fetch_gem_info(gem_name, version)
        cache_key = "info:#{gem_name}:#{version}"
        return cache.fetch(cache_key) if cache.key?(cache_key)

        uri = URI("#{@v2_api_base}/#{escape_path_component(gem_name)}/versions/#{escape_path_component(version)}.json")
        response = @http_get.call(uri)
        return unless successful_response?(response)

        cache[cache_key] = JSON.parse(response_body(response))
      end

      def parse_min_ruby(requirement)
        return if requirement.to_s.strip.empty?

        parsed = Gem::Requirement.new(requirement.to_s)
        parsed.requirements.each do |operator, version|
          return version if operator == ">="
        end
        parsed.requirements.each do |operator, version|
          return version if operator == "~>"
        end
        nil
      rescue ArgumentError
        nil
      end

      private

      def normalize_requirements(requirements)
        values = Array(requirements).flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?)
        return if values.empty?

        Gem::Requirement.new(values)
      end

      def successful_response?(response)
        code = response_code(response).to_i
        code >= 200 && code < 300
      end

      def response_code(response)
        response.respond_to?(:code) ? response.code : response.fetch(:code)
      end

      def response_body(response)
        response.respond_to?(:body) ? response.body : response.fetch(:body)
      end

      def escape_path_component(value)
        URI.encode_www_form_component(value.to_s)
      end
    end
    README_DEFAULT_PRESERVE_SECTIONS = ["synopsis", "configuration", "basic usage"].freeze
    README_DEFAULT_PRESERVE_PATTERNS = ["note:*"].freeze
    README_INTEGRATIONS = %w[codecov coveralls qlty codeql].freeze
    README_INTEGRATION_BADGE_PATTERNS = {
      "codecov" => [
        /\s*\[!\[CodeCov Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
        /\n\[!\[Coverage Graph\]\[[^\]]+\]\]\[[^\]]+\]\n/,
      ],
      "coveralls" => [
        /\s*\[!\[Coveralls Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
      ],
      "qlty" => [
        /\s*\[!\[QLTY Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
        /\s*\[!\[QLTY Maintainability\]\[[^\]]+\]\]\[[^\]]+\]/,
      ],
      "codeql" => [
        /\s*\[!\[CodeQL\]\[[^\]]+\]\]\[[^\]]+\]/,
      ],
    }.freeze
    README_SECTION_ALIASES = {
      "summary" => "synopsis",
      "usage" => "basic usage",
      "configuration options" => "configuration",
      "setup" => "basic usage",
    }.freeze
    README_STATIC_TOP_LOGO_ROW = "[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang]"
    README_STATIC_TOP_LOGO_REFS = [
      "[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg",
      "[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN",
      "[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg",
      "[🖼️ruby-lang]: https://www.ruby-lang.org/",
    ].join("\n").freeze
    VAR_HOME_PREFIX = %r{\A/var/home(?=/|\z)}
    VAR_HOME_TEXT = %r{/var/home(?=/|\z)}
    RUBOCOP_VERSION_MAP = [
      [Gem::Version.new("1.8"), "~> 0.1"],
      [Gem::Version.new("1.9"), "~> 2.0"],
      [Gem::Version.new("2.0"), "~> 4.0"],
      [Gem::Version.new("2.1"), "~> 6.0"],
      [Gem::Version.new("2.2"), "~> 8.0"],
      [Gem::Version.new("2.3"), "~> 10.0"],
      [Gem::Version.new("2.4"), "~> 12.0"],
      [Gem::Version.new("2.5"), "~> 14.0"],
      [Gem::Version.new("2.6"), "~> 16.0"],
      [Gem::Version.new("2.7"), "~> 18.0"],
      [Gem::Version.new("3.0"), "~> 20.0"],
      [Gem::Version.new("3.1"), "~> 22.0"],
      [Gem::Version.new("3.2"), "~> 24.0"],
      [Gem::Version.new("3.3"), "~> 26.0"],
      [Gem::Version.new("3.4"), "~> 28.0"],
    ].freeze
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

    class PluginRegistry
      Hook = Struct.new(:plugin_name, :phase, :timing, :callback, keyword_init: true)
      VALID_TIMINGS = %i[before after].freeze

      attr_reader :hooks, :configured_plugins, :loaded_plugins, :load_errors

      def initialize(configured_plugins: [], loaded_plugins: [])
        @hooks = []
        @configured_plugins = configured_plugins
        @loaded_plugins = loaded_plugins
        @load_errors = []
      end

      def register(plugin_name:, phase:, timing:, &callback)
        raise ArgumentError, "Plugin callbacks require a block" unless callback

        @hooks << Hook.new(
          plugin_name: plugin_name.to_s,
          phase: normalize_phase(phase),
          timing: normalize_timing(timing),
          callback: callback
        )
      end

      def run(timing:, phase:, context:, actor:, phase_stats:)
        normalized_phase = normalize_phase(phase)
        normalized_timing = normalize_timing(timing)
        hooks_for(normalized_timing, normalized_phase).each do |hook|
          hook.callback.call(
            context: context,
            actor: actor,
            phase: normalized_phase,
            phase_stats: phase_stats,
            plugin_name: hook.plugin_name
          )
        end
      end

      def empty?
        @hooks.empty?
      end

      private

      def hooks_for(timing, phase)
        @hooks.select { |hook| hook.timing == timing && hook.phase == phase }
      end

      def normalize_phase(phase)
        value = phase.to_s.strip
        raise ArgumentError, "Plugin phase cannot be blank" if value.empty?

        value.downcase.to_sym
      end

      def normalize_timing(timing)
        value = timing.to_s.strip.downcase.to_sym
        return value if VALID_TIMINGS.include?(value)

        raise ArgumentError, "Unsupported plugin timing #{timing.inspect}"
      end
    end

    class PluginRegistrar
      attr_reader :plugin_name

      def initialize(plugin_name:, registry:)
        @plugin_name = plugin_name.to_s
        @registry = registry
      end

      def on_phase(phase, timing: :after, &block)
        @registry.register(plugin_name: plugin_name, phase: phase, timing: timing, &block)
      end

      def before_phase(phase, &block)
        on_phase(phase, timing: :before, &block)
      end

      def after_phase(phase, &block)
        on_phase(phase, timing: :after, &block)
      end
    end

    module PluginLoader
      REGISTRATION_METHOD = :register_kettle_jem_plugin

      module_function

      def load!(plugin_names:)
        names = normalize_plugin_names(plugin_names)
        registry = PluginRegistry.new(configured_plugins: names, loaded_plugins: names)
        names.each { |plugin_name| load_plugin!(plugin_name, registry: registry) }
        registry
      end

      def load_plugin!(plugin_name, registry:)
        require(plugin_require_path(plugin_name))
        handle = plugin_handle(plugin_name)
        unless handle.respond_to?(REGISTRATION_METHOD)
          raise Error, "Plugin #{plugin_name.inspect} does not implement #{REGISTRATION_METHOD}."
        end

        handle.public_send(
          REGISTRATION_METHOD,
          PluginRegistrar.new(plugin_name: plugin_name, registry: registry)
        )
      rescue LoadError => e
        raise Error, "Could not load plugin #{plugin_name.inspect}: #{e.message}"
      end

      def normalize_plugin_names(plugin_names)
        Array(plugin_names).flatten.map { |name| name.to_s.strip }.reject(&:empty?).uniq
      end

      def plugin_require_path(plugin_name)
        plugin_name.to_s.tr("-", "/")
      end

      def plugin_handle(plugin_name)
        constant_name = plugin_name.to_s.split("-").map { |part| camelize(part) }.join("::")
        constant_name.split("::").inject(Object) { |scope, name| scope.const_get(name) }
      rescue NameError => e
        raise Error, "Could not resolve plugin handle for #{plugin_name.inspect}: #{e.message}"
      end

      def camelize(value)
        value.to_s.split("_").map(&:capitalize).join
      end
    end

    class PluginContext
      attr_reader :project_root, :mode, :facts, :recipe_pack, :recipe_reports, :phase_reports,
        :changed_files, :diagnostics, :helpers, :out

      def initialize(project_root:, mode:, facts:, recipe_pack:, recipe_reports:, changed_files:, diagnostics:, phase_reports: [])
        @project_root = project_root
        @mode = mode
        @facts = facts
        @recipe_pack = recipe_pack
        @recipe_reports = recipe_reports
        @phase_reports = phase_reports
        @changed_files = changed_files
        @diagnostics = diagnostics
        @helpers = PluginHelpers.new(project_root: project_root, changed_files: changed_files, diagnostics: diagnostics)
        @out = PluginOutput.new(diagnostics: diagnostics)
      end
    end

    class PluginHelpers
      def initialize(project_root:, changed_files:, diagnostics:)
        @project_root = project_root
        @changed_files = changed_files
        @diagnostics = diagnostics
      end

      def record_template_result(path, action)
        relative_path = relative_project_path(path)
        @changed_files << relative_path unless @changed_files.include?(relative_path)
        @diagnostics << {
          kind: "plugin_file_change",
          path: relative_path,
          action: action.to_s
        }
      end

      private

      def relative_project_path(path)
        expanded = File.expand_path(path.to_s, @project_root)
        root = File.expand_path(@project_root)
        expanded.start_with?("#{root}/") ? expanded.delete_prefix("#{root}/") : path.to_s
      end
    end

    class PluginOutput
      def initialize(diagnostics:)
        @diagnostics = diagnostics
      end

      def report_detail(message)
        @diagnostics << { kind: "plugin_detail", message: message.to_s }
      end

      def warning(message)
        @diagnostics << { kind: "plugin_warning", message: message.to_s }
      end
    end

    module TemplateChecksums
      YAML_KEY = "kettle-jem"
      CHECKSUMS_SUBKEY = "checksums"
      VERSION_SUBKEY = "version"

      module_function

      def compute(template_root:)
        root = template_root.to_s.chomp("/")
        checksums = {}
        Find.find(root) do |path|
          next unless File.file?(path)

          relative_path = path.delete_prefix("#{root}/")
          checksums[relative_path] = Digest::SHA256.file(path).hexdigest
        end
        checksums.sort.to_h
      end

      def load_stored(config_path:)
        return {} unless File.exist?(config_path.to_s)

        data = YAML.safe_load_file(config_path.to_s, permitted_classes: [], aliases: false)
        entry = data.is_a?(Hash) ? data[YAML_KEY] : nil
        stored = entry.is_a?(Hash) ? entry[CHECKSUMS_SUBKEY] : nil
        stored.is_a?(Hash) ? stored : {}
      rescue StandardError
        {}
      end

      def diff(current:, stored:)
        current_keys = current.keys.to_set
        stored_keys = stored.keys.to_set

        {
          added: (current_keys - stored_keys).sort,
          changed: (current_keys & stored_keys).select { |path| current[path] != stored[path] }.sort,
          removed: (stored_keys - current_keys).sort,
        }
      end

      def diff_count(diff)
        diff.fetch(:added, []).size + diff.fetch(:changed, []).size + diff.fetch(:removed, []).size
      end

      def summary(diff)
        count = diff_count(diff)
        return "no template files changed since last run" if count.zero?

        parts = []
        parts << "#{diff.fetch(:added, []).size} added" if diff.fetch(:added, []).any?
        parts << "#{diff.fetch(:changed, []).size} changed" if diff.fetch(:changed, []).any?
        parts << "#{diff.fetch(:removed, []).size} removed" if diff.fetch(:removed, []).any?
        "#{count} template file(s) since last run: #{parts.join(", ")}"
      end

      def detail_lines(diff)
        [
          *diff.fetch(:added, []).map { |path| "  + #{path}" },
          *diff.fetch(:changed, []).map { |path| "  ~ #{path}" },
          *diff.fetch(:removed, []).map { |path| "  - #{path}" },
        ]
      end

      def build_yaml_block(checksums:, version: nil)
        lines = [YAML_KEY]
        lines[0] = "#{lines[0]}:"
        lines << "  #{VERSION_SUBKEY}: #{version.to_s.dump}" if version
        lines << "  #{CHECKSUMS_SUBKEY}:"
        checksums.sort.each do |path, sha|
          lines << "    #{path.dump}: #{sha.dump}"
        end
        lines.join("\n")
      end

      def write_to_config(config_path:, checksums:, version: nil)
        return unless File.exist?(config_path.to_s)

        content = File.read(config_path.to_s)
        new_block = build_yaml_block(checksums: checksums, version: version)
        updated =
          if content.match?(/^#{Regexp.escape(YAML_KEY)}:\s*(?:#[^\n]*)?\n/)
            content.gsub(/^#{Regexp.escape(YAML_KEY)}:[^\n]*\n(?:[ \t][^\n]*\n)*/, "#{new_block}\n")
          else
            "#{content.rstrip}\n\n#{new_block}\n"
          end
        File.write(config_path.to_s, updated)
      end
    end

    module TemplatingReport
      REPORT_DIR = File.join("tmp", "kettle-jem").freeze
      REPORT_PREFIX = "templating-report"
      MERGE_GEM_NAMES = %w[
        ast-merge
        bash-merge
        dotenv-merge
        json-merge
        markdown-merge
        markly-merge
        prism-merge
        psych-merge
        rbs-merge
        toml-merge
      ].freeze

      module_function

      def snapshot(loaded_specs: Gem.loaded_specs, workspace_root: default_workspace_root)
        {
          kettle_jem: build_entry("kettle-jem", loaded_specs["kettle-jem"], workspace_root: workspace_root),
          workspace_root: workspace_root,
          merge_gems: MERGE_GEM_NAMES.map { |name| build_entry(name, loaded_specs[name], workspace_root: workspace_root) },
        }
      end

      def build_entry(name, spec, workspace_root:)
        path = spec&.full_gem_path.to_s
        {
          name: name,
          version: spec&.version&.to_s,
          path: path.empty? ? nil : path,
          local_path: !path.empty? && local_path?(path, workspace_root: workspace_root),
          loaded: !spec.nil?,
        }
      end

      def default_workspace_root
        env_root = ENV["KETTLE_RB_DEV"].to_s.strip
        return if env_root.casecmp("false").zero?

        repo_root = File.expand_path("../../..", __dir__)
        sibling_root = File.expand_path("..", repo_root)
        if env_root.empty? || env_root.casecmp("true").zero?
          return canonical_path(sibling_root) if File.directory?(File.join(sibling_root, "nomono"))

          return
        end
        canonical_path(env_root)
      end

      def local_path?(path, workspace_root: default_workspace_root)
        return false if workspace_root.to_s.strip.empty?

        expanded_path = canonical_path(path)
        expanded_root = canonical_path(workspace_root)
        expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}/")
      end

      def canonical_path(path)
        File.realpath(path)
      rescue StandardError
        File.expand_path(path)
      end

      def console_lines(snapshot: nil, project_root: nil)
        snapshot ||= self.snapshot
        merge_gems = snapshot.fetch(:merge_gems, [])
        return [] if merge_gems.empty?

        lines = []
        kettle_jem = snapshot[:kettle_jem]
        header = "[kettle-jem] Templating merge environment"
        header += " (kettle-jem #{kettle_jem[:version]})" if kettle_jem&.dig(:version)
        lines << header
        workspace_root = snapshot[:workspace_root]
        lines << "  workspace root: #{Kettle::Jem.display_path(workspace_root)}" if workspace_root
        merge_gems.each do |entry|
          version = entry[:version] || "not loaded"
          path = entry[:path] ? " - #{Kettle::Jem.display_path(entry[:path])}" : ""
          lines << "  - #{entry[:name]} #{version} (#{source_label(entry)})#{path}"
        end
        local_workspace_warning_lines(snapshot: snapshot, project_root: project_root).each { |line| lines << "  #{line}" }
        lines
      end

      def markdown_section(snapshot: nil)
        snapshot ||= self.snapshot
        merge_gems = snapshot.fetch(:merge_gems, [])
        return "" if merge_gems.empty?

        lines = ["## Merge Gem Environment", ""]
        workspace_root = snapshot[:workspace_root]
        if workspace_root
          lines << "**Workspace root**: `#{Kettle::Jem.display_path(workspace_root)}`"
          lines << ""
        end
        lines << "| Gem | Version | Source | Path |"
        lines << "|-----|---------|--------|------|"
        merge_gems.each do |entry|
          version = entry[:version] || "_not loaded_"
          path = entry[:path] ? "`#{Kettle::Jem.display_path(entry[:path])}`" : ""
          lines << "| #{entry[:name]} | #{version} | #{source_label(entry)} | #{path} |"
        end
        lines << ""
        lines.join("\n")
      end

      def render_markdown(project_root:, output_dir: nil, snapshot: nil, run_started_at: Time.now, finished_at: nil,
        status: nil, warnings: [], error: nil, template_diff: nil, template_commit_sha: nil)
        snapshot ||= self.snapshot
        lines = ["# kettle-jem Templating Run Report", ""]
        lines << "**Started**: #{run_started_at.iso8601}"
        lines << "**Finished**: #{finished_at.iso8601}" if finished_at
        lines << "**Status**: `#{status}`" if status
        lines << "**Project root**: `#{Kettle::Jem.display_path(project_root)}`"
        lines << "**Output dir**: `#{Kettle::Jem.display_path(output_dir)}`" if output_dir
        if (kettle_jem = snapshot[:kettle_jem])
          path = kettle_jem[:path] ? " `#{Kettle::Jem.display_path(kettle_jem[:path])}`" : ""
          lines << "**kettle-jem**: #{kettle_jem[:version] || "unknown"} (#{source_label(kettle_jem)})#{path}"
        end
        if (warning = local_workspace_warning(snapshot: snapshot, project_root: project_root))
          lines << ""
          lines << local_warning_section(warning)
        end
        lines << "**Template commit**: `#{template_commit_sha}`" if template_commit_sha
        lines << ""
        lines << template_diff_section(template_diff) if template_diff
        section = markdown_section(snapshot: snapshot)
        lines << section unless section.empty?
        unique_warnings = Array(warnings).map(&:to_s).reject { |warning| warning.strip.empty? }.uniq
        if unique_warnings.any?
          lines << "## Warnings"
          lines << ""
          unique_warnings.each { |warning| lines << "- #{warning}" }
          lines << ""
        end
        if error
          lines << "## Error"
          lines << ""
          lines << "```text"
          lines << "#{error.class}: #{error.message}"
          Array(error.backtrace).first(10).each { |line| lines << line }
          lines << "```"
          lines << ""
        end
        lines.join("\n")
      end

      def report_path(project_root:, output_dir: nil, run_started_at: Time.now, pid: Process.pid)
        target_root = output_dir || project_root
        timestamp = run_started_at.utc.strftime("%Y%m%d-%H%M%S-%6N")
        File.join(target_root, REPORT_DIR, "#{REPORT_PREFIX}-#{timestamp}-#{pid}.md")
      end

      def write(project_root:, output_dir: nil, snapshot: nil, report_path: nil, run_started_at: Time.now,
        finished_at: nil, status: nil, warnings: [], error: nil, template_diff: nil, template_commit_sha: nil)
        snapshot ||= self.snapshot
        report_path ||= self.report_path(project_root: project_root, output_dir: output_dir, run_started_at: run_started_at)
        FileUtils.mkdir_p(File.dirname(report_path))
        File.write(
          report_path,
          render_markdown(
            project_root: project_root,
            output_dir: output_dir,
            snapshot: snapshot,
            run_started_at: run_started_at,
            finished_at: finished_at,
            status: status,
            warnings: warnings,
            error: error,
            template_diff: template_diff,
            template_commit_sha: template_commit_sha
          )
        )
        report_path
      end

      def source_label(entry)
        return "not loaded" unless entry[:loaded]
        return "local path" if entry[:local_path]

        "installed gem"
      end

      def local_workspace_warning_lines(snapshot:, project_root:)
        warning = local_workspace_warning(snapshot: snapshot, project_root: project_root)
        return [] unless warning

        [
          "WARNING: #{warning}",
          "Hint: set KETTLE_RB_DEV=true (or configure it in .env.local) to use sibling workspace gems.",
        ]
      end

      def local_warning_section(warning)
        <<~MARKDOWN.chomp
          ## Local Workspace Warning

          #{warning}

          Set `KETTLE_RB_DEV=true` (or configure it in `.env.local`) to use sibling workspace gems instead of the installed release.
        MARKDOWN
      end

      def local_workspace_warning(snapshot:, project_root:)
        return if project_root.to_s.strip.empty?

        kettle_jem = snapshot[:kettle_jem]
        return unless kettle_jem&.fetch(:loaded, false)
        return if kettle_jem[:local_path]

        workspace_root = sibling_workspace_root(project_root)
        return unless workspace_root

        local_checkout = File.join(workspace_root, "kettle-jem")
        return unless File.directory?(local_checkout)

        loaded_path = canonical_path(kettle_jem[:path].to_s)
        checkout_path = canonical_path(local_checkout)
        return if loaded_path == checkout_path

        env_value = ENV.fetch("KETTLE_RB_DEV", "<unset>")
        "Detected sibling workspace checkout at `#{Kettle::Jem.display_path(local_checkout)}`, but this run is using installed `kettle-jem` " \
          "(KETTLE_RB_DEV=#{env_value.inspect})."
      end

      def sibling_workspace_root(project_root)
        candidate = canonical_path(File.expand_path("..", project_root))
        return unless File.directory?(File.join(candidate, "nomono"))

        candidate
      end

      def template_diff_section(diff)
        lines = ["## Template File Changes", ""]
        if Kettle::Jem::TemplateChecksums.diff_count(diff).zero?
          lines << "_No template files changed since last run._"
          lines << ""
          return lines.join("\n")
        end
        lines << Kettle::Jem::TemplateChecksums.summary(diff)
        lines << ""
        {added: "Added", changed: "Changed", removed: "Removed"}.each do |key, label|
          next unless diff.fetch(key, []).any?

          lines << "### #{label} (#{diff.fetch(key).size})"
          lines << ""
          diff.fetch(key).each { |path| lines << "- `#{path}`" }
          lines << ""
        end
        lines.join("\n")
      end
    end

    module SelfTest
      module Manifest
        module_function

        def generate(dir)
          result = {}
          dir = dir.to_s
          return result unless Dir.exist?(dir)

          Find.find(dir) do |path|
            next if File.directory?(path)

            content = File.binread(path)
            relative_path = path.sub(%r{^#{Regexp.escape(dir)}/?}, "")
            result[relative_path] = Digest::SHA256.hexdigest(content) unless relative_path.empty?
          rescue StandardError
            next
          end
          result.sort.to_h
        end

        def compare(before, after)
          all_keys = (before.keys | after.keys).sort
          result = {matched: [], changed: [], added: [], removed: []}
          all_keys.each do |key|
            before_sha = before[key]
            after_sha = after[key]
            if before_sha.nil?
              result[:added] << key
            elsif after_sha.nil?
              result[:removed] << key
            elsif before_sha == after_sha
              result[:matched] << key
            else
              result[:changed] << key
            end
          end
          result
        end
      end

      module Reporter
        module_function

        def diff(file_a, file_b)
          a = File.exist?(file_a.to_s) ? file_a.to_s : "/dev/null"
          b = File.exist?(file_b.to_s) ? file_b.to_s : "/dev/null"
          out, = Open3.capture2("diff", "-u", a, b)
          out
        rescue Errno::ENOENT
          a_lines = File.exist?(file_a.to_s) ? File.readlines(file_a) : []
          b_lines = File.exist?(file_b.to_s) ? File.readlines(file_b) : []
          return "" if a_lines == b_lines

          ["--- #{file_a}", "+++ #{file_b}", *a_lines.map { |line| "-#{line.chomp}" }, *b_lines.map { |line| "+#{line.chomp}" }].join("\n") + "\n"
        end

        def summary(comparison, output_dir:, templating_environment: nil, diff_count: nil, now: Time.now)
          matched = comparison.fetch(:matched, [])
          changed = comparison.fetch(:changed, [])
          added = comparison.fetch(:added, [])
          removed = comparison.fetch(:removed, [])
          skipped = comparison.fetch(:skipped, [])
          diff_count = changed.size if diff_count.nil?
          total = matched.size + changed.size + added.size + removed.size
          score = total.zero? ? 0.0 : (matched.size.to_f / total * 100).round(1)
          divergence = (100.0 - score).round(1)

          lines = ["# Template Self-Test Report", ""]
          lines << "**Date**: #{now.iso8601}"
          lines << "**Output**: `#{output_dir}`"
          lines << "**Score**: #{score}% (#{matched.size}/#{total} files unchanged)"
          lines << "**Divergence**: #{divergence}% (#{changed.size + added.size + removed.size}/#{total} files changed, added, or missing)"
          lines << ""
          environment_section = Kettle::Jem::TemplatingReport.markdown_section(snapshot: templating_environment) if templating_environment
          lines << environment_section if environment_section && !environment_section.empty?
          append_self_test_table(lines, "Changed Files", changed, "modified")
          append_self_test_table(lines, "New Files", added)
          if removed.any?
            lines << "## Not Templated - Unexpected (#{removed.size})"
            lines << ""
            lines << "These files exist in the source gem and appear to be within the template's"
            lines << "scope, but were not produced by the template task."
            lines << ""
            lines << "| File |"
            lines << "|------|"
            removed.each { |path| lines << "| #{path} |" }
            lines << ""
          end
          if changed.empty? && added.empty? && removed.empty?
            lines << "## All files match! :tada:"
          else
            lines << "## Detailed Diffs"
            lines << ""
            lines << if diff_count.to_i.positive?
              "See `report/diffs/` directory (#{diff_count} file#{"s" unless diff_count == 1})."
            else
              "No per-file diffs were generated for this run; `report/diffs/` is empty."
            end
          end
          append_skipped_files(lines, skipped)
          lines << ""
          lines.join("\n")
        end

        def append_self_test_table(lines, title, paths, status = nil)
          return if paths.empty?

          lines << "## #{title} (#{paths.size})"
          lines << ""
          if status
            lines << "| File | Status |"
            lines << "|------|--------|"
            paths.each { |path| lines << "| #{path} | #{status} |" }
          else
            lines << "| File |"
            lines << "|------|"
            paths.each { |path| lines << "| #{path} |" }
          end
          lines << ""
        end

        def append_skipped_files(lines, skipped)
          return if skipped.empty?

          lines << ""
          lines << "<details>"
          lines << "<summary>Not Templated (#{skipped.size} files) - source-only files not produced by the template task</summary>"
          lines << ""
          lines << "These files are part of the gem source and are not expected to appear in the template output."
          lines << ""
          lines << "| File |"
          lines << "|------|"
          skipped.each { |path| lines << "| #{path} |" }
          lines << ""
          lines << "</details>"
        end
      end
    end

    module_function

    def display_path(path)
      return path if path.nil?

      path.to_s.sub(VAR_HOME_PREFIX, "/home")
    end

    def display_text(text)
      return text if text.nil?

      text.to_s.gsub(VAR_HOME_TEXT, "/home")
    end

    def packaged_template_root
      PACKAGED_TEMPLATE_ROOT
    end

    def template_root_path(project_root = Dir.pwd, config: nil)
      root = File.expand_path(project_root.to_s)
      resolved_config = config || kettle_jem_config(root)
      templates = resolved_config["templates"].is_a?(Hash) ? resolved_config["templates"] : {}
      template_root(root, templates).fetch(:path)
    end

    def template_manifest(project_root: Dir.pwd, template_root: nil, config: nil)
      root = template_root || template_root_path(project_root, config: config)
      {
        kind: "kettle_jem_template_manifest",
        version: 1,
        template_root: root,
        checksums: TemplateChecksums.compute(template_root: root),
      }
    end

    def appraisal_gem_abbreviation(gem_name)
      APPRAISAL_GEM_ABBREVIATIONS.fetch(gem_name.to_s, gem_name.to_s)
    end

    def appraisal_format_version(version)
      version.to_s.tr(".", "-")
    end

    def appraisal_name(tier1_gem:, tier1_version:, ruby_series:, tier2_gem: nil, tier2_version: nil)
      parts = [
        APPRAISAL_NAME_PREFIX,
        appraisal_gem_abbreviation(tier1_gem),
        appraisal_format_version(tier1_version),
      ]
      unless tier2_gem.to_s.empty?
        parts << appraisal_gem_abbreviation(tier2_gem)
        parts << appraisal_format_version(tier2_version)
      end
      parts << ruby_series.to_s
      parts.join("-")
    end

    def appraisal_modular_gemfile_path(gem_name:, version:, ruby_series:)
      File.join("gemfiles", "modular", gem_name.to_s, ruby_series.to_s, "v#{version}.gemfile")
    end

    def appraisal_modular_gemfile_content(gem_name:, version:, sub_dependencies: {})
      lines = [
        "# frozen_string_literal: true",
        "",
        "# Generated by kettle-jem",
        "",
        %(gem "#{gem_name}", "#{appraisal_version_requirement(version)}"),
      ]
      sub_dependencies.each do |name, requirement|
        lines << %(gem "#{name}", "~> #{requirement}")
      end
      ensure_trailing_newline(lines.join("\n"))
    end

    def appraisal_version_requirement(version)
      segments = version.to_s.split(".")
      segments.length >= 3 ? "~> #{version}" : "~> #{version}.0"
    end

    def appraisal_file_content(matrix_entries)
      lines = [
        "# frozen_string_literal: true",
        "",
        "# Generated by kettle-jem",
        "# Do not edit directly; regenerate from Kettle/Jem appraisal matrix metadata.",
        "",
      ]
      matrix_entries.each do |entry|
        lines << %(appraise "#{entry.fetch(:name)}" do)
        lines << %(  eval_gemfile "#{entry.fetch(:tier1_gemfile)}") if entry[:tier1_gemfile]
        lines << %(  eval_gemfile "#{entry.fetch(:tier2_gemfile)}") if entry[:tier2_gemfile]
        lines << %(  eval_gemfile "#{entry.fetch(:x_std_libs_gemfile)}") if entry[:x_std_libs_gemfile]
        lines << "end"
        lines << ""
      end
      ensure_trailing_newline(lines.join("\n"))
    end

    def appraisal_workflow_groups(matrix_entries, bucket_ranges:, exec_cmd: "rake spec")
      grouped = Hash.new { |hash, key| hash[key] = [] }
      normalized_ranges = bucket_ranges.transform_values do |range|
        {
          floor: Gem::Version.new((range[:floor] || range["floor"]).to_s),
          ceiling: Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s),
        }
      end
      matrix_entries.each do |entry|
        ruby_series = entry[:ruby_series] || entry["ruby_series"]
        range = normalized_ranges[ruby_series]
        next unless range

        lifecycle = appraisal_workflow_lifecycle(range.fetch(:floor))
        grouped[lifecycle] << {
          ruby: appraisal_workflow_ruby(range.fetch(:floor), lifecycle),
          appraisal: entry[:name] || entry["name"],
          exec_cmd: exec_cmd,
          gemfile: "Appraisal.root",
          rubygems: "latest",
          bundler: "latest",
        }
      end
      grouped.transform_values { |entries| entries.sort_by { |entry| entry.fetch(:appraisal).to_s } }
    end

    def appraisal_workflow_yaml_snippets(matrix_entries, bucket_ranges:, exec_cmd: "rake spec")
      appraisal_workflow_groups(matrix_entries, bucket_ranges: bucket_ranges, exec_cmd: exec_cmd).transform_values do |entries|
        lines = ["strategy:", "  matrix:", "    include:"]
        entries.each do |entry|
          lines << %(      - ruby: "#{entry.fetch(:ruby)}")
          lines << %(        appraisal: "#{entry.fetch(:appraisal)}")
          lines << %(        exec_cmd: "#{entry.fetch(:exec_cmd)}")
          lines << %(        gemfile: "#{entry.fetch(:gemfile)}")
          lines << %(        rubygems: "#{entry.fetch(:rubygems)}")
          lines << %(        bundler: "#{entry.fetch(:bundler)}")
        end
        lines.join("\n")
      end
    end

    def appraisal_workflow_lifecycle(ruby_floor)
      APPRAISAL_WORKFLOW_LIFECYCLE_RANGES.each do |name, range|
        return name if ruby_floor.between?(range.fetch(:min), range.fetch(:max))
      end
      ruby_floor < APPRAISAL_WORKFLOW_LIFECYCLE_RANGES.fetch("ancient").fetch(:min) ? "ancient" : "current"
    end

    def appraisal_workflow_ruby(ruby_floor, lifecycle)
      return "ruby" if lifecycle == "current"

      segments = ruby_floor.segments
      "#{segments[0]}.#{segments[1] || 0}"
    end

    def appraisal_x_stdlib_exclusions(template_content)
      gems = template_content.to_s.lines.filter_map do |line|
        line[%r{eval_gemfile\s+["']\.\./([\w-]+)/}, 1]
      end
      (gems + APPRAISAL_ALWAYS_EXCLUDED_GEMS).uniq.sort
    end

    def appraisal_select_versions(version_metadata, mode:, requirements: nil)
      mode = mode.to_s
      raise ArgumentError, "invalid appraisal version selection mode: #{mode}" unless APPRAISAL_VERSION_SELECTION_MODES.include?(mode)

      versions = appraisal_filtered_versions(version_metadata, requirements: requirements)
      return versions if mode == "patch"

      by_major = appraisal_minor_versions_by_major(versions)
      return [] if by_major.empty?

      current_major = by_major.last.fetch(:major)
      case mode
      when "major"
        by_major.map { |entry| entry.fetch(:minors).last }
      when "minor"
        by_major.flat_map { |entry| entry.fetch(:minors) }
      when "minor-minmax"
        by_major.flat_map do |entry|
          minors = entry.fetch(:minors)
          entry.fetch(:major) < current_major ? [minors.first, minors.last].uniq : minors
        end
      when "semver"
        by_major.flat_map do |entry|
          entry.fetch(:major) < current_major ? [entry.fetch(:minors).last] : entry.fetch(:minors)
        end
      end
    end

    def appraisal_matrix_entries(tier1_gems:, tier2_gems: [])
      entries = []
      tier1_gems.each do |tier1|
        tier1_name = tier1[:name] || tier1["name"]
        assignments = tier1[:assignments] || tier1["assignments"] || []
        assignments.each do |assignment|
          tier1_version = assignment[:version] || assignment["version"]
          ruby_series = assignment[:bucket] || assignment["bucket"] || assignment[:ruby_series] || assignment["ruby_series"]
          if tier2_gems.empty?
            entries << appraisal_matrix_entry(
              tier1_name: tier1_name,
              tier1_version: tier1_version,
              ruby_series: ruby_series,
            )
          else
            tier2_gems.each do |tier2|
              tier2_name = tier2[:name] || tier2["name"]
              Array(tier2[:versions] || tier2["versions"]).each do |tier2_version|
                entries << appraisal_matrix_entry(
                  tier1_name: tier1_name,
                  tier1_version: tier1_version,
                  ruby_series: ruby_series,
                  tier2_name: tier2_name,
                  tier2_version: tier2_version,
                )
              end
            end
          end
        end
      end
      entries
    end

    def appraisal_matrix_entry(tier1_name:, tier1_version:, ruby_series:, tier2_name: nil, tier2_version: nil)
      {
        name: appraisal_name(
          tier1_gem: tier1_name,
          tier1_version: tier1_version,
          tier2_gem: tier2_name,
          tier2_version: tier2_version,
          ruby_series: ruby_series,
        ),
        tier1_gemfile: appraisal_modular_gemfile_path(gem_name: tier1_name, version: tier1_version, ruby_series: ruby_series),
        tier2_gemfile: tier2_name ? appraisal_modular_gemfile_path(gem_name: tier2_name, version: tier2_version, ruby_series: ruby_series) : nil,
        x_std_libs_gemfile: File.join("gemfiles", "modular", "x_std_libs", ruby_series.to_s, "libs.gemfile"),
        ruby_series: ruby_series.to_s,
      }
    end

    def appraisal_filtered_versions(version_metadata, requirements:)
      requirement = requirements ? Gem::Requirement.new(Array(requirements)) : nil
      version_metadata.filter_map do |entry|
        number = entry[:number] || entry["number"]
        next if number.to_s.empty?
        next if entry[:prerelease] || entry["prerelease"]
        next if requirement && !requirement.satisfied_by?(Gem::Version.new(number))

        number.to_s
      end.sort_by { |version| Gem::Version.new(version) }
    end

    def appraisal_minor_versions_by_major(versions)
      versions.map do |version|
        gem_version = Gem::Version.new(version)
        segments = gem_version.segments
        {
          major: segments[0],
          minor: "#{segments[0]}.#{segments[1] || 0}",
        }
      end.uniq.group_by { |entry| entry.fetch(:major) }.map do |major, entries|
        {
          major: major,
          minors: entries.map { |entry| entry.fetch(:minor) }.sort_by { |minor| Gem::Version.new(minor) },
        }
      end.sort_by { |entry| entry.fetch(:major) }
    end

    def appraisal_find_ruby_seams(version_metadata)
      minors = appraisal_latest_patch_by_minor(version_metadata)
      seams = []
      previous = nil
      minors.sort_by { |minor, _entry| Gem::Version.new(minor) }.each do |minor, entry|
        min_ruby = Gem::Version.new((entry[:min_ruby] || entry["min_ruby"]).to_s)
        min_ruby = [min_ruby, APPRAISAL_MINIMUM_RUBY_FLOOR].max
        if previous.nil? || min_ruby > previous
          seams << { version: minor, min_ruby: min_ruby }
        end
        previous = min_ruby
      end
      seams
    end

    def appraisal_ruby_series(version_metadata, project_min_ruby: nil)
      floors = appraisal_find_ruby_seams(version_metadata).map { |seam| seam.fetch(:min_ruby) }
      if project_min_ruby
        floor = Gem::Version.new(project_min_ruby.to_s)
        floors.reject! { |version| version < floor }
        floors << floor unless floors.include?(floor)
      end
      floors = [Gem::Version.new("3.2")] if floors.empty?
      appraisal_minor_versions_to_buckets(floors.map { |version| appraisal_minor_key(version) }.uniq.sort)
    end

    def appraisal_assign_version_buckets(selected_versions:, seams:, buckets:, bucket_ranges:, all_versions:)
      return [] if selected_versions.empty? || buckets.empty?

      normalized_ranges = appraisal_normalized_bucket_ranges(bucket_ranges)
      version_min_rubies = appraisal_version_min_ruby_map(all_versions, seams)
      assignments = selected_versions.sort_by { |version| Gem::Version.new(version) }.filter_map do |version|
        min_ruby = version_min_rubies[version]
        next unless min_ruby

        next_seam = appraisal_next_seam_ruby(version, min_ruby, all_versions, version_min_rubies)
        bucket = next_seam ? appraisal_bucket_below(next_seam, buckets, normalized_ranges) : buckets.last
        { version: version, bucket: bucket } if bucket
      end
      appraisal_fill_bucket_gaps(assignments, buckets, normalized_ranges, version_min_rubies, all_versions)
    end

    def appraisal_latest_patch_by_minor(version_metadata)
      version_metadata.each_with_object({}) do |entry, latest|
        number = (entry[:number] || entry["number"]).to_s
        next if number.empty?

        version = Gem::Version.new(number)
        minor = "#{version.segments[0]}.#{version.segments[1] || 0}"
        current = latest[minor]
        latest[minor] = entry if current.nil? || version > Gem::Version.new((current[:number] || current["number"]).to_s)
      end
    end

    def appraisal_minor_versions_to_buckets(minor_versions)
      by_major = minor_versions.group_by { |minor| minor.split(".").first.to_i }
      buckets = []
      ranges = {}
      by_major.each do |major, minors|
        sorted = minors.sort_by { |minor| Gem::Version.new(minor) }
        sorted.each_with_index do |minor, index|
          bucket = index == sorted.length - 1 ? "r#{major}" : "r#{major}.#{[sorted[index + 1].split(".").last.to_i - 1, minor.split(".").last.to_i].max}"
          next if ranges.key?(bucket)

          buckets << bucket
          ceiling = index == sorted.length - 1 ? "#{major}.99" : bucket.split(".").last ? "#{major}.#{bucket.split(".").last}" : "#{major}.99"
          ranges[bucket] = { floor: Gem::Version.new(minor), ceiling: Gem::Version.new(ceiling) }
        end
      end
      { buckets: buckets.sort_by { |bucket| appraisal_bucket_sort_key(bucket) }, bucket_ranges: ranges }
    end

    def appraisal_minor_key(version)
      segments = Gem::Version.new(version.to_s).segments
      "#{segments[0]}.#{segments[1] || 0}"
    end

    def appraisal_bucket_sort_key(bucket)
      match = bucket.to_s.match(/\Ar(\d+)(?:\.(\d+))?\z/)
      [match[1].to_i, match[2] ? match[2].to_i : 999]
    end

    def appraisal_normalized_bucket_ranges(bucket_ranges)
      bucket_ranges.transform_values do |range|
        {
          floor: Gem::Version.new((range[:floor] || range["floor"]).to_s),
          ceiling: Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s),
        }
      end
    end

    def appraisal_version_min_ruby_map(all_versions, seams)
      sorted_seams = seams.sort_by { |seam| Gem::Version.new(seam[:version] || seam["version"]) }
      seam_index = 0
      current = nil
      all_versions.sort_by { |version| Gem::Version.new(version) }.each_with_object({}) do |version, map|
        while seam_index < sorted_seams.length && Gem::Version.new(sorted_seams[seam_index][:version] || sorted_seams[seam_index]["version"]) <= Gem::Version.new(version)
          current = Gem::Version.new((sorted_seams[seam_index][:min_ruby] || sorted_seams[seam_index]["min_ruby"]).to_s)
          current = [current, APPRAISAL_MINIMUM_RUBY_FLOOR].max
          seam_index += 1
        end
        map[version] = current if current
      end
    end

    def appraisal_next_seam_ruby(version, min_ruby, all_versions, version_min_rubies)
      found = false
      all_versions.sort_by { |candidate| Gem::Version.new(candidate) }.each do |candidate|
        found ||= Gem::Version.new(candidate) >= Gem::Version.new(version)
        next unless found

        candidate_ruby = version_min_rubies[candidate]
        return candidate_ruby if candidate_ruby && candidate_ruby > min_ruby
      end
      nil
    end

    def appraisal_bucket_below(ruby_floor, buckets, bucket_ranges)
      buckets.filter_map do |bucket|
        range = bucket_ranges[bucket]
        next unless range && range.fetch(:ceiling) < ruby_floor

        [bucket, range.fetch(:ceiling)]
      end.max_by(&:last)&.first
    end

    def appraisal_fill_bucket_gaps(assignments, buckets, bucket_ranges, version_min_rubies, all_versions)
      covered = assignments.map { |assignment| assignment.fetch(:bucket) }
      (buckets - covered).each do |bucket|
        range = bucket_ranges[bucket]
        next unless range

        filler = all_versions.sort_by { |version| Gem::Version.new(version) }.reverse.find do |version|
          ruby = version_min_rubies[version]
          ruby && ruby.between?(range.fetch(:floor), range.fetch(:ceiling))
        end
        filler ||= all_versions.sort_by { |version| Gem::Version.new(version) }.reverse.find do |version|
          ruby = version_min_rubies[version]
          ruby && ruby <= range.fetch(:ceiling)
        end
        assignments << { version: filler, bucket: bucket, filler: true } if filler
      end
      assignments.sort_by { |assignment| bucket_ranges.fetch(assignment.fetch(:bucket)).fetch(:floor) }
    end

    def appraisal_resolve_sub_dependencies(parent_gem:, parent_version:, parent_versions:, dependency_versions:, ruby_min: nil, excluded_gems: [])
      parent = appraisal_latest_version_matching(parent_versions, parent_version)
      return {} unless parent

      ruby_floor = Gem::Version.new(ruby_min.to_s) unless ruby_min.to_s.empty?
      excluded = excluded_gems.map(&:to_s)
      Array(parent[:runtime_dependencies] || parent["runtime_dependencies"]).each_with_object({}) do |dependency, resolved|
        name = (dependency[:name] || dependency["name"]).to_s
        next if name.empty? || excluded.include?(name)

        requirement = begin
          Gem::Requirement.new(dependency[:requirements] || dependency["requirements"] || ">= 0")
        rescue ArgumentError
          Gem::Requirement.default
        end
        selected = appraisal_select_dependency_version(
          Array(dependency_versions[name] || dependency_versions[name.to_sym]),
          requirement: requirement,
          ruby_min: ruby_floor
        )
        resolved[name] = selected if selected
      end
    end

    def appraisal_latest_version_matching(version_metadata, requested_version)
      prefix = "#{requested_version}."
      version_metadata.select do |entry|
        number = (entry[:number] || entry["number"]).to_s
        number == requested_version.to_s || number.start_with?(prefix)
      end.max_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
    end

    def appraisal_select_dependency_version(version_metadata, requirement:, ruby_min:)
      compatible = version_metadata.select do |entry|
        number = (entry[:number] || entry["number"]).to_s
        !number.empty? && requirement.satisfied_by?(Gem::Version.new(number))
      end.sort_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
      return if compatible.empty?

      if ruby_min
        selected = compatible.reverse.find do |entry|
          min_ruby = entry[:min_ruby] || entry["min_ruby"]
          min_ruby.to_s.empty? || Gem::Version.new(min_ruby.to_s) <= ruby_min
        end
        return (selected || compatible.first).then { |entry| entry[:number] || entry["number"] }
      end
      compatible.last.then { |entry| entry[:number] || entry["number"] }
    end

    def appraisal_stale_gemfile_paths(existing_paths:, current_entries:)
      current_names = current_entries.map { |entry| (entry[:name] || entry["name"]).to_s }.to_set
      existing_paths.map(&:to_s).select do |path|
        basename = File.basename(path, ".gemfile")
        path.start_with?("gemfiles/#{APPRAISAL_NAME_PREFIX}-") &&
          path.end_with?(".gemfile") &&
          !current_names.include?(basename)
      end.sort
    end

    def appraisal_extract_runtime_dependencies(gemspec_content)
      gemspec_content.to_s.lines.filter_map do |line|
        stripped = line.lstrip
        next if stripped.start_with?("#")

        stripped[/add_(?:runtime_)?dependency\s*\(?\s*["']([^"']+)["']/, 1]
      end.uniq
    end

    def appraisal_scaffold_config(gemspec_content:, existing_config: {}, exclusions: [], default_mode: "semver", freshness_ttl: APPRAISAL_DEFAULT_FRESHNESS_TTL)
      excluded = exclusions.map(&:to_s).to_set
      runtime_dependencies = appraisal_extract_runtime_dependencies(gemspec_content)
      tier1 = runtime_dependencies.reject { |name| excluded.include?(name) }.map { |name| { "name" => name } }
      config = deep_string_key_hash(existing_config)
      matrix = config["appraisal_matrix"] || {}
      gems = matrix["gems"] || {}

      matrix["mode"] ||= default_mode
      matrix["freshness_ttl"] ||= freshness_ttl
      gems["tier1"] = tier1
      gems["tier2"] ||= []
      matrix["gems"] = gems
      config["appraisal_matrix"] = matrix
      config
    end

    def appraisal_matrix_has_versions?(matrix)
      gems = deep_string_key_hash(matrix || {}).fetch("gems", {})
      %w[tier1 tier2].any? do |tier|
        Array(gems[tier]).any? { |gem_config| Array(gem_config["versions"]).any? }
      end
    end

    def appraisal_matrix_fresh?(matrix, now: Time.now.to_i)
      resolved_at = (matrix || {})[:resolved_at] || (matrix || {})["resolved_at"]
      return false unless resolved_at

      ttl = (matrix || {})[:freshness_ttl] || (matrix || {})["freshness_ttl"] || APPRAISAL_DEFAULT_FRESHNESS_TTL
      (now.to_i - resolved_at.to_i) < ttl.to_i
    end

    def appraisal_time_ago(timestamp, now: Time.now.to_i)
      return "unknown" unless timestamp

      seconds = now.to_i - timestamp.to_i
      return "#{seconds / 60}m" if seconds < 3600
      return "#{seconds / 3600}h" if seconds < 86_400

      "#{seconds / 86_400}d"
    end

    def appraisal_all_versions_for(resolver:, gem_name:, mode:, requirements: nil, include_versions: nil, exclude_versions: nil)
      base_versions = if mode.to_s == "patch"
        resolver.versions(gem_name, requirements: requirements).map { |entry| entry[:number] || entry["number"] }
      else
        resolver.minor_versions_by_major(gem_name, requirements: requirements).flat_map { |entry| entry[:minors] || entry["minors"] }
      end
      appraisal_finalize_versions(base_versions, include_versions: include_versions, exclude_versions: exclude_versions)
    end

    def appraisal_finalize_versions(base_versions, include_versions: nil, exclude_versions: nil)
      merged = appraisal_sort_versions(Array(base_versions) + Array(include_versions))
      excluded = Array(exclude_versions).map(&:to_s).to_set
      return merged if excluded.empty?

      appraisal_sort_versions(merged.reject { |version| excluded.include?(version) })
    end

    def appraisal_compatible_version_for_bucket?(resolver:, gem_name:, version:, ruby_series:, bucket_ranges:)
      range = bucket_ranges[ruby_series] || bucket_ranges[ruby_series.to_s]
      return true unless range

      ceiling = Gem::Version.new(((range[:ceiling] || range["ceiling"]).to_s))
      exact_version = appraisal_latest_minor_patch(resolver: resolver, gem_name: gem_name, version: version)
      min_ruby = resolver.min_ruby_version(gem_name, exact_version)
      min_ruby.nil? || Gem::Version.new(min_ruby.to_s) <= ceiling
    rescue StandardError
      true
    end

    def appraisal_latest_minor_patch(resolver:, gem_name:, version:)
      all_versions = resolver.versions(gem_name)
      prefix = "#{version}."
      matching = all_versions.select do |entry|
        number = (entry[:number] || entry["number"]).to_s
        number == version.to_s || number.start_with?(prefix)
      end
      return version.to_s if matching.empty?

      latest = matching.max_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
      (latest[:number] || latest["number"]).to_s
    end

    def appraisal_sort_versions(values)
      values.compact.map(&:to_s).reject(&:empty?).uniq.sort_by { |version| Gem::Version.new(version) }
    end

    def deep_string_key_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), converted|
          converted[key.to_s] = deep_string_key_hash(child)
        end
      when Array
        value.map { |child| deep_string_key_hash(child) }
      else
        value
      end
    end

    def discover_facts(project_root, env: ENV)
      gemspec_path = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
      raise ArgumentError, "no gemspec found in #{project_root}" unless gemspec_path

      gemspec = File.read(gemspec_path)
      name = extract_gemspec_assignment(gemspec, "spec.name") || File.basename(gemspec_path, ".gemspec")
      homepage_url = extract_gemspec_assignment(gemspec, "spec.homepage")
      metadata_source_url = extract_metadata_value(gemspec, "source_code_uri")
      source_url = concrete_github_url(metadata_source_url) || concrete_github_url(homepage_url) || metadata_source_url || homepage_url

      kettle_config = kettle_jem_config(project_root)
      author = author_facts(gemspec, kettle_config, env)
      copyright = copyright_facts(project_root, kettle_config)
      license = license_facts(
        kettle_config,
        extract_gemspec_array(gemspec, "spec.licenses"),
        author: author,
        author_email: author[:email],
        copyright: copyright
      )
      project_runtime = project_runtime_facts(
        kettle_config,
        env,
        package_name: name,
        source_url: source_url,
        author_domain: author[:domain],
        min_ruby: extract_gemspec_assignment(gemspec, "spec.required_ruby_version"),
        version: extract_gemspec_assignment(gemspec, "spec.version")
      )
      facts = {
        package: compact_hash(
          ecosystem: "rubygems",
          name: name,
          slug: name,
          description: extract_gemspec_assignment(gemspec, "spec.description") ||
            extract_gemspec_assignment(gemspec, "spec.summary"),
          homepage_url: homepage_url,
          source_url: source_url,
          license_expression: license[:expression],
        ),
        rubygems: compact_hash(
          gemspec_path: File.basename(gemspec_path),
          namespace: classify_namespace(name),
          min_ruby: extract_gemspec_assignment(gemspec, "spec.required_ruby_version"),
        ),
      }
      bootstrap = kettle_config_bootstrap_facts(project_root, env)
      facts[:kettle_config_bootstrap] = bootstrap if bootstrap
      facts[:author] = author unless author.empty?
      facts[:copyright] = copyright unless copyright.empty?
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
      legacy_cleanups = template_legacy_destination_cleanups(project_root, template_preferences)
      template_facts[:legacy_destination_cleanups] = legacy_cleanups unless legacy_cleanups.empty?
      unless template_preferences.empty?
        facts[:license] = license unless license.empty?
        facts[:project_runtime] = project_runtime unless project_runtime.empty?
        readme_logo = readme_logo_facts(kettle_config, package_name: name, github_org: project_runtime[:github_org])
        facts[:readme_logo] = readme_logo unless readme_logo.empty?
        readme_style = readme_style_facts(project_root, kettle_config, license)
        facts[:readme_style] = readme_style unless readme_style.empty?
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
      if facts[:kettle_config_bootstrap]
        recipes.unshift(kettle_config_bootstrap_recipe(facts.fetch(:kettle_config_bootstrap)))
      end
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
        recipe[:readme_style] = facts[:readme_style] if preference.fetch(:target_path) == "README.md" && facts[:readme_style]
        recipes << recipe
      end
      facts.dig(:templates, :legacy_destination_cleanups).to_a.each do |cleanup|
        recipes << recipe_entry(
          "template_legacy_destination_cleanup_#{workflow_recipe_slug(cleanup.fetch(:legacy_path))}",
          cleanup.fetch(:legacy_path),
          "file",
          "supplied_legacy_destination_file_deletion",
          facts: %w[templates]
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

    def plan_project(project_root, env: ENV, run_options: {})
      preflight_project!(project_root)
      decision_policy = decision_policy_for(env, run_options)
      facts = discover_facts(project_root, env: env)
      pack = recipe_pack(facts)
      files = read_project_files(project_root, pack)
      recipe_reports = pack.fetch(:recipes).map do |recipe|
        execute_recipe(project_root: project_root, recipe: recipe, facts: facts, files: files, decision_policy: decision_policy)
      end
      plugin_registry = plugin_registry_for_project(project_root)
      changed_files = recipe_reports.filter_map { |report| report[:relative_path] if report[:changed] }.sort
      diagnostics = recipe_reports.flat_map { |report| report[:diagnostics] }
      phase_reports = phase_reports_for(recipe_reports)
      decision_evaluations = recipe_reports.map { |report| report.fetch(:decision_evaluation) }
      unless plugin_registry.configured_plugins.empty?
        diagnostics << plugin_lifecycle_diagnostic(
          plugin_registry,
          callbacks_run: false,
          active_runner_phases: []
        )
      end
      run_stats = recipe_run_stats(recipe_reports, diagnostics: diagnostics)

      {
        mode: "plan",
        ready: true,
        facts: facts,
        recipe_pack: pack,
        recipe_reports: recipe_reports,
        phase_reports: phase_reports,
        decision_policy: decision_policy.to_h,
        decision_evaluations: decision_evaluations,
        changed_files: changed_files,
        diagnostics: diagnostics,
        run_stats: run_stats,
      }
    end

    def apply_project(project_root, env: ENV, run_options: {})
      report = plan_project(project_root, env: env, run_options: run_options).merge(mode: "apply")
      run_apply_phases(project_root, report)
      report
    end

    def plan_readme_style(project_root, env: ENV)
      facts = discover_facts(project_root, env: env)
      config = kettle_jem_config(project_root)
      readme_style = facts[:readme_style] ||
        readme_style_facts(project_root, config, facts.fetch(:license, {}))
      original_path = File.join(project_root, "README.md")
      original = File.exist?(original_path) ? File.read(original_path) : ""
      final_content = render_thin_readme(facts, readme_style, original, readme_preserve_config(config))

      {
        mode: "plan",
        readme_path: "README.md",
        changed: final_content != original,
        readme_style: readme_style,
        final_content: final_content,
        diagnostics: [],
      }
    end

    def apply_readme_style(project_root, env: ENV)
      report = plan_readme_style(project_root, env: env).merge(mode: "apply")
      return report unless report.fetch(:changed)

      path = File.join(project_root, report.fetch(:readme_path))
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, report.fetch(:final_content))
      report
    end

    def render_thin_readme(facts, readme_style, original, preserve_config)
      package = facts.fetch(:package)
      rubygems = facts.fetch(:rubygems)
      license_expression = package[:license_expression].to_s
      min_ruby = minimum_ruby_token(rubygems[:min_ruby])
      title = classify_namespace(package.fetch(:name))
      badges = [
        package[:source_url] && "[![Source](https://img.shields.io/badge/source-github-238636.svg)](#{package[:source_url]})",
        license_expression.empty? ? nil : "![License](https://img.shields.io/badge/license-#{shield_token(license_expression)}-259D6C.svg)",
      ].compact.join(" ")
      funding_enabled = readme_style.fetch(:floss_funding_enabled, false)
      security_enabled = readme_style.fetch(:security_enabled, false)
      section_partials = readme_section_partials_for_render(readme_style, facts)
      rendered = [
        "# 💎 #{title}",
        badges,
        "## 🌻 Synopsis\n\n#{section_partials.fetch("synopsis", "")}",
        "## 💡 Info you can shake a stick at\n\nCompatible with MRI Ruby #{min_ruby}+.\n\n#{readme_family_intro_and_backend_matrix}",
        "## ✨ Installation\n\n```console\ngem install #{package.fetch(:name)}\n```",
        "## ⚙️ Configuration\n\n#{section_partials.fetch("configuration", "")}",
        "## 🔧 Basic Usage\n\n#{section_partials.fetch("basic usage", "")}",
      ]
      rendered << "## 🦷 FLOSS Funding\n\nThis free software project accepts funding support when configured by the package maintainer." if funding_enabled
      rendered << "## 🔐 Security\n\nSee [SECURITY.md](SECURITY.md)." if security_enabled
      rendered.concat([
        "## 🤝 Contributing\n\nContributions are welcome. Missing optional service integrations are reported by the generator instead of rendered as broken badges.",
        "## 📌 Versioning\n\nThis project follows semantic versioning for its public API where practical.",
        "## 📄 License\n\nThis project is made available under the following license expression: #{license_expression.empty? ? "unspecified" : license_expression}.",
        "## 🤑 A request for help\n\nPlease support the project by using it, reporting issues, and contributing improvements.",
      ])
      template_content = rendered.reject(&:empty?).join("\n\n") + "\n"

      merge_readme_template(
        template_content: template_content,
        destination_content: original,
        preserve_config: readme_preserve_config_without_partial_sections(preserve_config, section_partials.keys)
      )
    end

    def readme_section_partials_for_render(readme_style, facts)
      partials = readme_style[:section_partials]
      return {} unless partials.is_a?(Hash)

      tokens = readme_template_tokens(facts)
      partials.each_with_object({}) do |(section, partial), result|
        content = partial.is_a?(Hash) ? partial[:content].to_s : partial.to_s
        next if content.strip.empty?

        result[normalize_readme_section_key(section)] = resolve_template_tokens(content, tokens)
      end
    end

    def readme_preserve_config_without_partial_sections(preserve_config, partial_sections)
      normalized_partials = partial_sections.map { |section| normalize_readme_section_key(section) }
      return preserve_config if normalized_partials.empty?

      config = (preserve_config || {}).dup
      sections = if config.key?(:sections)
        Array(config[:sections]).map { |section| normalize_readme_section_key(section) }
      else
        README_DEFAULT_PRESERVE_SECTIONS.dup
      end
      config[:sections] = sections.reject { |section| normalized_partials.include?(section) }
      config
    end

    def readme_template_tokens(facts)
      {
        "KJ|CB:USER" => "",
        "KJ|FUNDING:BUYMEACOFFEE" => "",
        "KJ|FUNDING:KOFI" => "",
        "KJ|FUNDING:LIBERAPAY" => "",
        "KJ|FUNDING:PATREON" => "",
        "KJ|FUNDING:PAYPAL" => "",
        "KJ|FUNDING:POLAR" => "",
        "KJ|GH:USER" => "",
        "KJ|GH_ORG" => github_org_from_url(facts.dig(:package, :source_url)).to_s,
        "KJ|GL:USER" => "",
        "KJ|PROJECT_EMOJI" => "💎",
        "KJ|README:COPYRIGHT_NOTICE" => "",
        "KJ|README:LICENSE_BADGE" => "",
        "KJ|README:LICENSE_COMPAT_BADGE" => "",
        "KJ|README:LICENSE_INTRO" => "",
        "KJ|README:LICENSE_REFS" => "",
        "KJ|README:TOP_LOGO_REFS" => "",
        "KJ|README:TOP_LOGO_ROW" => "",
        "KJ|SH:USER" => "",
        "KJ|SOCIAL:BLUESKY" => "",
        "KJ|SOCIAL:DEVTO" => "",
        "KJ|SOCIAL:LINKTREE" => "",
        "KJ|SOCIAL:MASTODON" => "",
        "KJ|YARD_HOST" => "rubydoc.info",
      }.merge(template_tokens(facts, facts.fetch(:funding, {})))
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
      unless h1_index
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

    def execute_recipe(project_root:, recipe:, facts:, files:, decision_policy:)
      relative_path = recipe.fetch(:target_path)
      destination_existed = File.exist?(File.join(project_root, relative_path))
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
      when /\Atemplate_legacy_destination_cleanup_/
        ""
      when /\Agithub_actions_workflow_snippets_/
        synchronize_github_actions_workflow_snippets(original)
      when "kettle_config_bootstrap"
        apply_kettle_config_bootstrap(project_root, recipe)
      when /\Atemplate_source_preference_/
        original
      when /\Atemplate_source_application_/
        apply_template_source(project_root, recipe, original, facts: facts)
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
      metadata = recipe_report_metadata(recipe).merge(destination_existed: destination_existed)
      decision_evaluation = recipe_decision_evaluation(
        decision_policy: decision_policy,
        recipe: recipe,
        changed: changed,
        destination_existed: destination_existed
      )
      metadata[:decision_evaluation] = decision_evaluation
      report = content_recipe_execution_report(
        request: request,
        final_content: final,
        changed: changed,
        step_reports: [step_report],
        diagnostics: [],
        metadata: metadata,
      )

      {
        recipe_name: recipe.fetch(:name),
        relative_path: relative_path,
        changed: changed,
        request_envelope: content_recipe_execution_request_envelope(request),
        report_envelope: content_recipe_execution_report_envelope(report),
        final_content: final,
        metadata: metadata,
        decision_evaluation: decision_evaluation,
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
        metadata: step_report_metadata(recipe, deletion).merge(
          ruby_template_policy_report(recipe: recipe, request: request, original: original, final: final)
        ),
      }
    end

    def ruby_template_policy_report(recipe:, request:, original:, final:)
      return {} unless recipe.fetch(:primitive) == "supplied_template_source_application"

      file_type = template_file_type(recipe)
      return {} unless %i[gemfile gemspec appraisals].include?(file_type)

      template_content = request.fetch(:template_content, "")
      report = {
        policy_kind: "kettle_jem_ruby_template_policy",
        file_type: file_type.to_s,
      }
      operations = case file_type
      when :gemfile
        gemfile_policy_operations(template_content, original, final, request)
      when :gemspec
        gemspec_policy_operations(template_content, original, final, request)
      when :appraisals
        appraisals_policy_operations(template_content, original, final, request)
      end
      report[:operations] = operations
      { ruby_template_policy: report }
    end

    def gemfile_policy_operations(template_content, original, final, request)
      package_name = runtime_context_value(request, :package, :name).to_s
      deleted = gemfile_dependency_names("#{template_content}\n#{original}") - gemfile_dependency_names(final)
      expected = ["appraisal"]
      expected << package_name unless package_name.empty?
      [
        {
          operation: "delete_dependency_declarations",
          deleted_gems: (deleted & expected).sort,
        },
      ]
    end

    def appraisals_policy_operations(template_content, original, final, request)
      package_name = runtime_context_value(request, :package, :name).to_s
      min_ruby = minimum_ruby_token(runtime_context_value(request, :rubygems, :min_ruby))
      source = "#{template_content}\n#{original}"
      [
        {
          operation: "merge_appraisal_blocks",
          inserted_appraisals: (appraisal_names(template_content) - appraisal_names(original)).sort,
          preserved_destination_appraisals: (appraisal_names(original) - appraisal_names(template_content) & appraisal_names(final)).sort,
        },
        {
          operation: "delete_self_dependency_declarations",
          deleted_dependency_count: [gemfile_dependency_names(source).count(package_name) - gemfile_dependency_names(final).count(package_name), 0].max,
        },
        {
          operation: "prune_minimum_ruby_appraisals",
          min_ruby: min_ruby,
          deleted_appraisals: (ruby_appraisal_names_below(original, min_ruby) - appraisal_names(final)).sort,
        },
      ]
    end

    def gemspec_policy_operations(template_content, original, final, request)
      template_receiver = gemspec_block_param(template_content) || "spec"
      destination_receiver = gemspec_block_param(original) || "spec"
      package_name = runtime_context_value(request, :package, :name).to_s
      self_dependency_names = gemspec_self_dependency_names(request, package_name)
      operations = [
        {
          operation: "preserve_project_fields",
          preserved_fields: gemspec_preserved_assignments(original, receiver: destination_receiver).keys.select do |field|
            final.include?("#{template_receiver}.#{field} =")
          end.sort,
        },
        {
          operation: "preserve_dependency_declarations",
          preserved_dependencies: gemspec_dependency_line_index(original, receiver: destination_receiver).keys.map(&:last).select do |gem_name|
            final.include?(%("#{gem_name}"))
          end.sort,
        },
        {
          operation: "delete_self_dependency_declarations",
          deleted_dependency_count: [
            gemspec_dependency_names("#{template_content}\n#{original}").count { |name| self_dependency_names.include?(name) } -
              gemspec_dependency_names(final).count { |name| self_dependency_names.include?(name) },
            0,
          ].max,
        },
      ]
      if template_receiver != destination_receiver
        operations << {
          operation: "normalize_gemspec_receiver",
          from: destination_receiver,
          to: template_receiver,
        }
      end
      operations
    end

    def runtime_context_value(request, *path)
      context = request[:runtime_context] || request["runtime_context"] || {}
      path.reduce(context) do |value, key|
        break nil unless value.respond_to?(:[])

        value[key] || value[key.to_s]
      end
    end

    def gemfile_dependency_names(content)
      content.to_s.lines.filter_map do |line|
        line[/^\s*gem\s+["']([^"']+)["']/, 1]
      end
    end

    def appraisal_names(content)
      content.to_s.lines.filter_map do |line|
        line[/^\s*appraise\s+["']([^"']+)["']\s+do\b/, 1]
      end
    end

    def ruby_appraisal_names_below(content, min_ruby)
      return [] if min_ruby.to_s.empty?

      minimum = Gem::Version.new(min_ruby.to_s)
      appraisal_names(content).select do |name|
        match = name.match(/\Aruby-(\d+)-(\d+)\z/)
        match && Gem::Version.new("#{match[1]}.#{match[2]}") < minimum
      end
    rescue ArgumentError
      []
    end

    def read_project_files(project_root, pack)
      pack.fetch(:recipes).to_h do |recipe|
        relative_path = recipe.fetch(:target_path)
        path = File.join(project_root, relative_path)
        [relative_path, File.exist?(path) ? File.read(path) : ""]
      end
    end

    def recipe_template_content(project_root, recipe)
      return "" unless %w[
        supplied_kettle_config_bootstrap
        supplied_template_source_preference
        supplied_template_source_application
      ].include?(recipe.fetch(:primitive))

      preference = recipe.fetch(:template_preference)
      path = File.join(
        preference.fetch(:source_root_path, project_root),
        preference.fetch(:source_relative_path, preference.fetch(:selected_source))
      )
      File.read(path)
    end

    def apply_template_source(project_root, recipe, original, facts: nil)
      strategy = recipe.dig(:template_preference, :strategy).to_s
      return original if strategy == "keep_destination"

      content = recipe_template_content(project_root, recipe)
      return content if strategy == "raw_copy"

      resolved = resolve_template_tokens(
        content,
        recipe.fetch(:template_tokens, {}),
        scan_unresolved: unresolved_template_scan?(recipe)
      )
    rescue ArgumentError => e
      raise ArgumentError, "#{recipe.fetch(:target_path)}: #{e.message}"
    else
      resolved = prepare_readme_template(resolved, recipe[:readme_style]) if recipe.fetch(:target_path) == "README.md"
      if recipe.fetch(:target_path) == "README.md" && (strategy.empty? || strategy == "merge")
        return merge_readme_template(
          template_content: resolved,
          destination_content: original,
          preserve_config: recipe.dig(:template_preference, :readme_preserve_config) || {}
        )
      end
      return merge_config_template_source(recipe, resolved, original, facts: facts) if strategy.empty? || strategy == "merge"

      resolved
    end

    def prepare_readme_template(content, readme_style)
      style = readme_style || {}
      prepared = prune_readme_integration_badges(content, style)
      omitted_sections = Array(style[:omitted_sections]).map(&:to_s)
      omitted_sections << "security" if style.key?(:security_enabled) && !style[:security_enabled]
      omitted_sections << "floss_funding" if style.key?(:floss_funding_enabled) && !style[:floss_funding_enabled]
      remove_readme_sections(prepared, omitted_sections.map { |section| section.tr("_", " ") })
    end

    def prune_readme_integration_badges(content, readme_style)
      integrations = Array(readme_style[:missing_integrations]) + Array(readme_style[:disabled_integrations])
      integrations.uniq.reduce(content.to_s) do |result, integration|
        README_INTEGRATION_BADGE_PATTERNS.fetch(integration.to_s, []).reduce(result) do |memo, pattern|
          memo.gsub(pattern, "")
        end
      end.gsub(/[ \t]{2,}/, " ")
    end

    def remove_readme_sections(content, section_bases)
      bases = section_bases.map { |section| normalize_readme_heading(section) }.uniq
      return content if bases.empty?

      sections = markdown_sections(content).select { |section| bases.include?(section.fetch(:base)) }
      return content if sections.empty?

      lines = content.to_s.split("\n", -1)
      sections.reverse_each do |section|
        lines[section.fetch(:start)..section.fetch(:end)] = []
      end
      ensure_trailing_newline(lines.join("\n").gsub(/\n{3,}/, "\n\n").strip)
    end

    def merge_config_template_source(recipe, template_content, destination_content, facts: nil)
      file_type = template_file_type(recipe)
      return template_content if destination_content.to_s.strip.empty?
      return destination_content if destination_content == template_content

      case file_type
      when :gemspec
        return merge_gemspec_template_source(template_content, destination_content, facts: facts)
      when :appraisals
        return merge_appraisals_template_source(template_content, destination_content, facts: facts)
      when :ruby, :gemfile, :rakefile
        merge_result = Ruby::Merge.merge_ruby(
          template_content,
          destination_content,
          "ruby",
          merge_template_requires: file_type == :rakefile,
          method_move_policy: ruby_method_move_policy(recipe)
        )
      when :yaml
        merge_result = Yaml::Merge.merge_yaml(template_content, destination_content, "yaml")
      when :toml
        merge_result = Toml::Merge.merge_toml(template_content, destination_content, "toml")
      else
        return template_content
      end
      if merge_result[:ok]
        output = merge_result.fetch(:output)
        if file_type == :gemfile
          output = merge_gemfile_eval_bucket_entries(template_content, output)
          return merge_gemfile_template_policy(output, facts: facts)
        end
        return merge_appraisals_template_policy(output, facts: facts) if file_type == :appraisals

        return output
      end

      diagnostics = merge_result.fetch(:diagnostics, [])
      message = diagnostics.map { |diagnostic| diagnostic[:message] || diagnostic["message"] }.compact.join("; ")
      raise ArgumentError, "failed to merge #{file_type} template #{recipe.fetch(:target_path)}: #{message}"
    end

    def ruby_method_move_policy(recipe)
      recipe.dig(:template_preference, :method_move_policy) || Ruby::Merge::DEFAULT_METHOD_MOVE_POLICY
    end

    def merge_gemfile_template_policy(content, facts:)
      package_name = facts.dig(:package, :name).to_s if facts
      removable_gems = ["appraisal"]
      removable_gems << package_name unless package_name.to_s.empty?
      remove_gemfile_dependency_lines(content, removable_gems)
    end

    def remove_gemfile_dependency_lines(content, gem_names)
      names = gem_names.map(&:to_s).reject(&:empty?).uniq
      return content if names.empty?

      lines = content.to_s.lines.reject do |line|
        match = line.match(/^\s*gem\s+["']([^"']+)["']/)
        match && names.include?(match[1])
      end
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def merge_gemfile_eval_bucket_entries(template_content, merged_content)
      template_entries = gemfile_eval_bucket_entries(template_content)
      return merged_content if template_entries.empty?

      template_by_key = template_entries.to_h { |entry| [entry.fetch(:key), entry] }
      emitted_paths = Set.new
      insert_at = nil
      lines = []
      merged_content.to_s.lines.each do |line|
        entry = gemfile_eval_bucket_entry(line)
        unless entry && template_by_key.key?(entry.fetch(:key))
          lines << line
          next
        end

        template_entry = template_by_key.fetch(entry.fetch(:key))
        if entry.fetch(:path) == template_entry.fetch(:path)
          lines << line unless emitted_paths.include?(entry.fetch(:path))
          emitted_paths << entry.fetch(:path)
        else
          insert_at ||= lines.length
        end
      end

      missing_lines = template_entries.reject { |entry| emitted_paths.include?(entry.fetch(:path)) }.map { |entry| entry.fetch(:line) }
      return ensure_trailing_newline(lines.join) if missing_lines.empty?

      insert_at ||= lines.length
      lines[insert_at, 0] = missing_lines
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def gemfile_eval_bucket_entries(content)
      content.to_s.lines.filter_map { |line| gemfile_eval_bucket_entry(line) }
    end

    def gemfile_eval_bucket_entry(line)
      path = line[/^\s*eval_gemfile\s+["']([^"']+)["']/, 1]
      return unless path

      key = path.sub(%r{/r\d+(?:\.\d+)?/}, "/{ruby}/")
      return if key == path

      { path: path, key: key, line: line }
    end

    def merge_appraisals_template_policy(content, facts:)
      package_name = facts.dig(:package, :name).to_s if facts
      min_ruby = minimum_ruby_token(facts.dig(:rubygems, :min_ruby)) if facts
      pruned = prune_appraisals_below_min_ruby(content, min_ruby)
      remove_gemfile_dependency_lines(pruned, [package_name])
    end

    def merge_appraisals_template_source(template_content, destination_content, facts:)
      template = appraisal_blocks(template_content)
      destination = appraisal_blocks(destination_content)
      ordered_blocks = template.fetch(:order).map { |name| template.fetch(:blocks).fetch(name) }
      destination.fetch(:order).each do |name|
        next if template.fetch(:blocks).key?(name)

        ordered_blocks << destination.fetch(:blocks).fetch(name)
      end
      prelude = template.fetch(:prelude).to_s.strip.empty? ? destination.fetch(:prelude) : template.fetch(:prelude)
      merged = ([prelude.to_s.rstrip] + ordered_blocks.map { |block| block.rstrip }).reject(&:empty?).join("\n\n")
      merge_appraisals_template_policy(ensure_trailing_newline(merged), facts: facts)
    end

    def appraisal_blocks(content)
      lines = content.to_s.lines
      prelude = []
      blocks = {}
      order = []
      index = 0
      while index < lines.length
        line = lines[index]
        match = line.match(/^\s*appraise\s+["']([^"']+)["']\s+do\b/)
        unless match
          prelude << line if blocks.empty?
          index += 1
          next
        end

        stop_index = skip_ruby_do_block(lines, index)
        name = match[1]
        unless blocks.key?(name)
          blocks[name] = lines[index...stop_index].join
          order << name
        end
        index = stop_index
      end
      { prelude: prelude.join, blocks: blocks, order: order }
    end

    def prune_appraisals_below_min_ruby(content, min_ruby)
      return content if min_ruby.to_s.empty?

      minimum = Gem::Version.new(min_ruby.to_s)
      lines = content.to_s.lines
      kept = []
      index = 0
      while index < lines.length
        line = lines[index]
        match = line.match(/^\s*appraise\s+["']ruby-(\d+)-(\d+)["']\s+do\b/)
        unless match
          kept << line
          index += 1
          next
        end

        appraisal_version = Gem::Version.new("#{match[1]}.#{match[2]}")
        if appraisal_version >= minimum
          kept << line
          index += 1
          next
        end

        index = skip_ruby_do_block(lines, index)
      end
      ensure_trailing_newline(kept.join.gsub(/\n{3,}/, "\n\n"))
    rescue ArgumentError
      content
    end

    def skip_ruby_do_block(lines, start_index)
      depth = 0
      index = start_index
      while index < lines.length
        line = lines[index]
        depth += line.scan(/\bdo\b/).length
        depth -= 1 if line.match?(/^\s*end\b/)
        index += 1
        break if depth <= 0
      end
      index
    end

    def merge_gemspec_template_source(template_content, destination_content, facts: nil)
      template_receiver = gemspec_block_param(template_content) || "spec"
      destination_receiver = gemspec_block_param(destination_content) || "spec"
      package_name = facts.dig(:package, :name).to_s if facts
      replacements = gemspec_preserved_assignments(destination_content, receiver: destination_receiver)
      merged = replacements.reduce(template_content.dup) do |content, (field, source_line)|
        pattern = /^(\s*#{Regexp.escape(template_receiver)}\.#{Regexp.escape(field)}\s*=\s*).*$/
        replacement = normalize_gemspec_receiver(source_line.rstrip, from: destination_receiver, to: template_receiver)
        content.match?(pattern) ? content.sub(pattern, replacement) : content
      end
      merged = preserve_gemspec_dependency_lines(
        merged,
        destination_content,
        template_receiver: template_receiver,
        destination_receiver: destination_receiver
      )
      remove_gemspec_self_dependency_lines(merged, package_name, receiver: template_receiver)
    end

    def gemspec_block_param(source)
      source.to_s[/Gem::Specification\.new\s+do\s+\|([^|]+)\|/, 1]&.strip
    end

    def normalize_gemspec_receiver(line, from:, to:)
      return line if from.to_s.empty? || to.to_s.empty? || from == to

      line.sub(/^(\s*)#{Regexp.escape(from)}\./, "\\1#{to}.")
    end

    def gemspec_preserved_assignments(source, receiver:)
      %w[
        name
        authors
        email
        summary
        description
        homepage
        licenses
        required_ruby_version
        executables
      ].each_with_object({}) do |field, assignments|
        line = source.to_s.lines.find do |candidate|
          candidate.match?(/^\s*#{Regexp.escape(receiver)}\.#{Regexp.escape(field)}\s*=/)
        end
        next unless line
        next if line.include?("TODO:")

        assignments[field] = line
      end
    end

    def preserve_gemspec_dependency_lines(template_content, destination_content, template_receiver:, destination_receiver:)
      destination_dependencies = gemspec_dependency_line_index(destination_content, receiver: destination_receiver).transform_values do |line|
        normalize_gemspec_receiver(line, from: destination_receiver, to: template_receiver)
      end
      return template_content if destination_dependencies.empty?

      merged = replace_matching_gemspec_dependency_lines(template_content, destination_dependencies, receiver: template_receiver)
      append_missing_gemspec_dependency_lines(merged, destination_dependencies, receiver: template_receiver)
    end

    def replace_matching_gemspec_dependency_lines(content, destination_dependencies, receiver:)
      content.to_s.lines.map do |line|
        key = gemspec_dependency_line_key(line, receiver: receiver)
        key && destination_dependencies[key] ? destination_dependencies[key] : line
      end.join
    end

    def append_missing_gemspec_dependency_lines(content, destination_dependencies, receiver:)
      existing_keys = gemspec_dependency_line_index(content, receiver: receiver).keys
      missing_lines = destination_dependencies.reject { |key, _line| existing_keys.include?(key) }.values
      return content if missing_lines.empty?

      content.sub(/^end\s*\z/, "#{missing_lines.join}end")
    end

    def gemspec_dependency_line_index(source, receiver:)
      source.to_s.lines.each_with_object({}) do |line, dependencies|
        key = gemspec_dependency_line_key(line, receiver: receiver)
        dependencies[key] ||= line if key
      end
    end

    def gemspec_dependency_names(source)
      source.to_s.lines.filter_map do |line|
        line[/^\s*\w+\.add_(?:development_|runtime_)?dependency\s*(?:\(|\s)\s*["']([^"']+)["']/, 1]
      end
    end

    def gemspec_self_dependency_names(request, package_name)
      names = [package_name.to_s]
      token_value = runtime_context_value(request, :template_tokens, "KJ|GEM_NAME")
      names << "{KJ|GEM_NAME}" if token_value.to_s == package_name.to_s
      names.reject(&:empty?).uniq
    end

    def remove_gemspec_self_dependency_lines(content, package_name, receiver:)
      name = package_name.to_s
      return content if name.empty?

      lines = content.to_s.lines.reject do |line|
        line.match?(/^\s*#{Regexp.escape(receiver)}\.add_(?:development_|runtime_)?dependency\s*(?:\(|\s)\s*["']#{Regexp.escape(name)}["']/)
      end
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def gemspec_dependency_line_key(line, receiver:)
      match = line.to_s.match(/^\s*#{Regexp.escape(receiver)}\.(add_(?:development_|runtime_)?dependency)\s*\(?\s*["']([^"']+)["']/)
      match && [match[1], match[2]]
    end

    def template_file_type(recipe)
      configured = recipe.dig(:template_preference, :file_type).to_s
      return configured.to_sym unless configured.empty?

      relative_path = recipe.fetch(:target_path).to_s
      basename = File.basename(relative_path)
      extension = File.extname(relative_path).downcase
      return :gemfile if basename == "Gemfile" || basename.end_with?(".gemfile")
      return :appraisals if basename.start_with?("Appraisals") || basename == "Appraisal.root.gemfile"
      return :gemspec if basename.end_with?(".gemspec")
      return :rakefile if basename == "Rakefile" || extension == ".rake"
      return :ruby if RUBY_TEMPLATE_BASENAMES.include?(basename) ||
        RUBY_TEMPLATE_SUFFIXES.any? { |suffix| basename.end_with?(suffix) } ||
        RUBY_TEMPLATE_EXTENSIONS.include?(extension)
      return :yaml if extension.match?(/\A\.ya?ml\z/) || File.basename(relative_path).casecmp("citation.cff").zero?
      return :toml if extension == ".toml"
      return :markdown if extension.match?(/\A\.md(?:own)?\z/)

      :text
    end

    def apply_kettle_config_bootstrap(project_root, recipe)
      content = recipe_template_content(project_root, recipe)
      tokens = stringify_template_tokens(recipe.fetch(:template_tokens, {}))
      content.gsub("{KJ|MIN_DIVERGENCE_THRESHOLD}", tokens.fetch("KJ|MIN_DIVERGENCE_THRESHOLD", ""))
    end

    def recipe_report_metadata(recipe)
      metadata = { packaging_recipe: recipe.fetch(:name) }
      metadata[:delete_file] = true if delete_file_recipe?(recipe)
      metadata[:template_source_preference] = deep_dup(recipe[:template_preference]) if recipe[:template_preference]
      metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      metadata[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
      metadata[:bootstrap_file] = true if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
      metadata
    end

    def decision_policy_for(env, run_options)
      DecisionPolicy.from_env(env || {}, **(run_options || {}))
    end

    def recipe_decision_evaluation(decision_policy:, recipe:, changed:, destination_existed:)
      decision_policy.resolve(
        id: "recipe:#{recipe.fetch(:name)}",
        category: recipe_decision_category(recipe),
        file: recipe.fetch(:target_path),
        default_action: recipe_default_action(recipe, changed: changed, destination_existed: destination_existed),
        severity: :advisory,
        diagnostics: recipe_decision_diagnostics(recipe)
      ).to_h
    end

    def recipe_decision_category(recipe)
      return "delete_file" if delete_file_recipe?(recipe)
      return "select_template_source" if recipe.fetch(:primitive) == "supplied_template_source_preference"
      return "bootstrap_config" if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
      return "apply_template_source" if recipe.fetch(:primitive) == "supplied_template_source_application"

      "merge_valid_document"
    end

    def recipe_default_action(recipe, changed:, destination_existed:)
      return "delete" if delete_file_recipe?(recipe)
      return "keep" unless changed
      return "create" unless destination_existed
      return "replace" if recipe.fetch(:primitive) == "supplied_template_source_application"

      "merge"
    end

    def recipe_decision_diagnostics(recipe)
      diagnostics = []
      if recipe.fetch(:primitive) == "supplied_template_source_application"
        diagnostics << "Non-interactive runs apply the configured template source default and report the decision."
      end
      if delete_file_recipe?(recipe)
        diagnostics << "Deletion is allowed only for explicit Kettle/Jem cleanup primitives."
      end
      diagnostics
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
      context[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
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
      if recipe.fetch(:primitive) == "supplied_legacy_destination_file_deletion"
        metadata.merge!(
          policy_kind: "delete_legacy_destination_file",
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
        metadata[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
      end
      if recipe.fetch(:primitive) == "supplied_template_source_application"
        metadata.merge!(
          policy_kind: "apply_template_source",
          operation: "replace",
          template_source_preference: deep_dup(recipe.fetch(:template_preference)),
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
      if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
        metadata.merge!(
          policy_kind: "bootstrap_kettle_config",
          operation: "create",
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

    def preflight_project!(project_root)
      paths = Dir.glob(File.join(project_root, "*.gemspec")).sort
      gemfile_path = File.join(project_root, "Gemfile")
      paths << gemfile_path if File.exist?(gemfile_path)
      paths.each { |path| preflight_ruby_syntax!(project_root, path) }
    end

    def preflight_ruby_syntax!(project_root, path)
      if defined?(RubyVM::InstructionSequence)
        RubyVM::InstructionSequence.compile_file(path)
      else
        _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", path)
        raise SyntaxError, stderr unless status.success?
      end
    rescue SyntaxError => e
      relative_path = path.delete_prefix("#{project_root}/")
      raise Error, "Preflight failed for #{relative_path}: #{e.message}"
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

    def plugin_registry_for_project(project_root)
      plugin_names = PluginLoader.normalize_plugin_names(plugin_names_from_config(kettle_jem_config(project_root)))
      registry = PluginRegistry.new(configured_plugins: plugin_names)
      plugin_names.each do |plugin_name|
        PluginLoader.load_plugin!(plugin_name, registry: registry)
        registry.loaded_plugins << plugin_name
      rescue Error => e
        registry.load_errors << {
          plugin_name: plugin_name,
          message: e.message
        }
      end
      registry
    end

    def plugin_names_from_config(config)
      raw = config.is_a?(Hash) ? config["plugins"] : nil
      case raw
      when Hash
        raw.each_with_object([]) do |(name, enabled), names|
          names << name unless falsey_config?(enabled)
        end
      else
        raw
      end
    end

    def plugin_lifecycle_diagnostic(plugin_registry, callbacks_run:, active_runner_phases:)
      {
        kind: "plugin_lifecycle",
        configured_plugins: plugin_registry.configured_plugins,
        loaded_plugins: plugin_registry.loaded_plugins,
        load_errors: plugin_registry.load_errors,
        registered_hooks: plugin_registry.hooks.map do |hook|
          {
            plugin_name: hook.plugin_name,
            phase: hook.phase.to_s,
            timing: hook.timing.to_s
          }
        end,
        callbacks_run: callbacks_run,
        active_runner_phases: active_runner_phases.map(&:to_s)
      }
    end

    def run_apply_phases(project_root, report)
      plugin_registry = plugin_registry_for_project(project_root)
      changed_files = report.fetch(:changed_files)
      diagnostics = report.fetch(:diagnostics)
      context = PluginContext.new(
        project_root: project_root,
        mode: "apply",
        facts: report.fetch(:facts),
        recipe_pack: report.fetch(:recipe_pack),
        recipe_reports: report.fetch(:recipe_reports),
        phase_reports: report.fetch(:phase_reports),
        changed_files: changed_files,
        diagnostics: diagnostics
      )
      reports_by_phase = report.fetch(:recipe_reports).group_by { |recipe_report| recipe_report_phase(recipe_report) }
      active_runner_phases = report.fetch(:phase_reports).map { |phase_report| phase_report.fetch(:phase).to_sym }
      active_runner_phases.each do |phase|
        phase_report = report.fetch(:phase_reports).find { |entry| entry.fetch(:phase).to_sym == phase }
        phase_stats = phase_report.fetch(:stats)
        unless plugin_registry.empty?
          plugin_registry.run(
            timing: :before,
            phase: phase,
            context: context,
            actor: self,
            phase_stats: phase_stats
          )
        end
        reports_by_phase.fetch(phase, []).each do |recipe_report|
          apply_recipe_report(project_root, recipe_report)
        end
        unless plugin_registry.empty?
          plugin_registry.run(
            timing: :after,
            phase: phase,
            context: context,
            actor: self,
            phase_stats: phase_stats
          )
        end
      end
      unless plugin_registry.configured_plugins.empty?
        diagnostics << plugin_lifecycle_diagnostic(
          plugin_registry,
          callbacks_run: true,
          active_runner_phases: active_runner_phases
        )
      end
      changed_files.sort!
      report[:run_stats] = recipe_run_stats(report.fetch(:recipe_reports), diagnostics: diagnostics)
    end

    def apply_recipe_report(project_root, recipe_report)
      return unless recipe_report[:changed]

      path = File.join(project_root, recipe_report.fetch(:relative_path))
      if recipe_report.dig(:metadata, :delete_file)
        FileUtils.rm_f(path)
      else
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, recipe_report.fetch(:final_content))
      end
    end

    def phase_reports_for(recipe_reports)
      reports_by_phase = recipe_reports.group_by { |recipe_report| recipe_report_phase(recipe_report) }
      PHASE_ORDER.map do |phase|
        reports = reports_by_phase.fetch(phase, [])
        changed_reports = reports.select { |recipe_report| recipe_report[:changed] }
        {
          phase: phase.to_s,
          recipes: reports.map { |recipe_report| recipe_report[:recipe_name] }.compact,
          changed_files: changed_reports.map { |recipe_report| recipe_report[:relative_path] }.compact.sort,
          stats: {
            recipe_count: reports.length,
            changed_count: changed_reports.length,
          },
        }
      end
    end

    def recipe_report_phase(recipe_report)
      phase_for_recipe(recipe_report[:recipe_name], recipe_report[:relative_path])
    end

    def phase_for_recipe(recipe_name, relative_path)
      path = relative_path.to_s
      name = recipe_name.to_s
      return :config_sync if path == ".kettle-jem.yml" || name.include?("kettle_config")
      return :dev_container if path.start_with?(".devcontainer/")
      return :github_workflows if path.start_with?(".github/workflows/") || path == ".github/FUNDING.yml"
      return :modular_gemfiles if path.start_with?("gemfiles/modular/")
      return :spec_helper if path == "spec/spec_helper.rb" || path.start_with?("spec/support/")
      return :environment_templates if path.start_with?(".env") || path.end_with?(".env")
      return :git_hooks if path.start_with?(".git/hooks/") || path.start_with?("git-hooks/")
      return :license_files if path.start_with?("LICENSE") || path.start_with?("NOTICE")
      return :duplicate_check if name.include?("duplicate")
      return :quality_config if quality_config_path?(path)

      :remaining_files
    end

    def quality_config_path?(path)
      %w[
        .rubocop.yml
        .reek.yml
        .standard.yml
        .simplecov
        .yardopts
        Rakefile
      ].include?(path)
    end

    def recipe_run_stats(recipe_reports, diagnostics: [])
      stats = {
        recipes: recipe_reports.length,
        created: 0,
        pre_existing: 0,
        identical: 0,
        changed: 0,
        deleted: 0,
        plugin_file_changes: diagnostics.count { |diagnostic| diagnostic[:kind] == "plugin_file_change" },
      }

      recipe_reports.each do |report|
        metadata = report.fetch(:metadata, {})
        if metadata[:delete_file]
          stats[:deleted] += 1 if report[:changed]
          next
        end

        if metadata[:destination_existed]
          stats[:pre_existing] += 1
          if report[:changed]
            stats[:changed] += 1
          else
            stats[:identical] += 1
          end
        elsif report[:changed]
          stats[:created] += 1
        end
      end

      stats[:summary] = recipe_run_stats_summary(stats)
      stats
    end

    def recipe_run_stats_summary(stats)
      [
        "recipes #{stats.fetch(:recipes)}",
        "created #{stats.fetch(:created)}",
        "pre_existing #{stats.fetch(:pre_existing)}",
        "identical #{stats.fetch(:identical)}",
        "changed #{stats.fetch(:changed)}",
        "deleted #{stats.fetch(:deleted)}",
        "plugin_file_changes #{stats.fetch(:plugin_file_changes)}",
      ].join(" ")
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
        "KJ|GEM_SHIELD" => shield_token(package.fetch(:name).to_s),
        "KJ|GEM_MAJOR" => gem_major_token(facts.fetch(:project_runtime, {})[:version]),
        "KJ|GH_ORG" => facts.fetch(:project_runtime, {})[:github_org].to_s,
        "KJ|NAMESPACE" => rubygems.fetch(:namespace).to_s,
        "KJ|NAMESPACE_SHIELD" => shield_token(rubygems.fetch(:namespace).to_s),
        "KJ|MIN_RUBY" => minimum_ruby_token(rubygems[:min_ruby]),
        "KJ|MIN_DEV_RUBY" => minimum_dev_ruby_token(rubygems[:min_ruby]),
      }.merge(
        rubocop_template_tokens(rubygems[:min_ruby])
      ).merge(
        author_template_tokens(facts.fetch(:author, {}))
      ).merge(
        forge_template_tokens(facts.fetch(:forge, {}))
      ).merge(
        funding_template_tokens(funding)
      ).merge(
        social_template_tokens(facts.fetch(:social, {}))
      ).merge(
        license_template_tokens(facts.fetch(:license, {}))
      ).merge(
        project_runtime_template_tokens(facts.fetch(:project_runtime, {}))
      ).merge(
        readme_logo_template_tokens(facts.fetch(:readme_logo, {}))
      )
      org = funding[:open_collective_org].to_s
      tokens["KJ|OPENCOLLECTIVE_ORG"] = org unless org.empty?
      tokens["KJ|README:FAMILY_INTRO_BACKEND_MATRIX"] = readme_family_intro_and_backend_matrix

      tokens.reject { |key, value| value.empty? && !EMPTY_TEMPLATE_TOKENS.include?(key) }
    end

    def readme_family_intro_and_backend_matrix
      [
        "<details markdown=\"1\">",
        "<summary>StructuredMerge package family and backend compatibility</summary>",
        "",
        "StructuredMerge packages provide fixture-backed merge behavior for document, configuration, source, archive, and binary formats. Shared contracts live in fixtures, while Go, Ruby, Rust, and TypeScript packages expose language-native APIs over the same behavior.",
        "",
        "| Package | Layer | Families | Status | README role |",
        "|---|---|---|---|---|",
        "| ast-template | workflow | template, readme | active | applies shared templates, package README sections, and package-directory sync workflows |",
        "| ast-merge | core | template, review, structured-edit | active | documents provider-neutral contracts, token resolution, review state, and execution reports |",
        "| tree-haver | backend substrate | parser, backend | active | documents backend selection, language-pack integration, position data, and capability reporting |",
        "| markdown-merge | family | markdown | active | documents Markdown heading, fenced-code, nested-family, and provider behavior |",
        "| json-merge | family | json, jsonc | active | documents JSON and JSONC merge behavior; old jsonc-merge is superseded |",
        "| toml-merge | family | toml | active | documents TOML table, value, parser, and backend behavior |",
        "| yaml-merge | family | yaml | active | documents YAML mapping, sequence, scalar, and backend behavior |",
        "| ruby-merge | family | ruby-source | active | documents Ruby source merge behavior; old prism-merge is backend/provider prior art |",
        "| zip-merge | family | zip, archive | active | documents ZIP member planning and raw-preservation behavior |",
        "| binary-merge | family | binary | active | documents binary preservation and diagnostics behavior |",
        "",
        "JSONC migration note: JSONC is handled by `json-merge` as the `jsonc` dialect. The old `jsonc-merge` package name is superseded in the cross-language toolset; only Ruby may grow a legacy `require \"jsonc/merge\"` wrapper if packaging compatibility requires it. Current fixture-backed JSONC claims are parse support and comment-neutral owner structure; comment-preserving merge output, freeze blocks, and JSONC emitter behavior need dedicated fixtures before they appear in package examples.",
        "",
        "YAML provider note: `yaml-merge` is the canonical YAML family package. Ruby's `psych-merge` package is the Psych provider for that family, not a separate YAML family; old `Psych::Merge::*` examples remain provider-specific until portable fixtures cover the behavior.",
        "",
        "Markdown provider note: `markdown-merge` is the canonical Markdown family package. Provider packages own parser-specific docs and backend defaults: Go `goldmarkmerge`, Ruby `commonmarker-merge`, `markly-merge`, and `kramdown-merge`, Rust `pulldown-cmark-merge`, and TypeScript `@structuredmerge/markdown-it-merge`.",
        "",
        "| Backend | Languages | Families | Note |",
        "|---|---|---|---|",
        "| tree-sitter-language-pack | Go, Ruby, Rust, TypeScript | markdown, toml, yaml, source | Preferred cross-language parser substrate where a family has language-pack support. |",
        "| native ecosystem parser | Ruby | ruby, yaml, markdown, toml | Backend-specific Ruby packages are provider prior art or adapters, not the source schema. |",
        "| plain structured text | Go, Ruby, Rust, TypeScript | plain, binary, zip | Families without parser requirements document preservation, byte ranges, archive members, and diagnostics. |",
        "",
        "| Compatibility claim | Current disposition | Fixture source |",
        "|---|---|---|",
        "| Old Ruby runtime backend tables | Prior art only; not a cross-language support promise | slice-741 backend/platform reconciliation |",
        "| tree-sitter-language-pack | Current portable parser substrate for Go, Ruby, Rust, and TypeScript | slices 122, 135, 171, 195, 215 |",
        "| Native parser/adaptor backends | Implementation-specific providers documented through family fixtures | slices 122 and 183 |",
        "| bash-merge, dotenv-merge, rbs-merge | Excluded from generated support tables until explicit scope decisions exist | slice-741 unresolved package list |",
        "",
        "| Reusable example | README role | Source fixture |",
        "|---|---|---|",
        "| Freeze tokens | Show how destination-owned regions are preserved without filling project-specific usage sections | slice-743 reusable README configuration examples |",
        "| Match preference | Summarize template-wins and destination-wins conflict choices through current policy vocabulary | slice-743 reusable README configuration examples |",
        "| Template-only behavior | Explain accept/skip handling for unmatched template entries | slice-743 reusable README configuration examples |",
        "| Debug report inspection | Point users to structured reports and diagnostics instead of ad hoc debug prose | slice-743 reusable README configuration examples |",
        "| Backend selection | Describe portable backend selection without old Ruby runtime support tables | slice-743 reusable README configuration examples |",
        "| Package-directory README command | Document plan/apply/convergence workflow for shared README updates | slice-743 reusable README configuration examples |",
        "",
        "</details>",
      ].join("\n")
    end

    def minimum_ruby_token(requirement)
      requirement.to_s[/\d+(?:\.\d+){1,2}/].to_s
    end

    def minimum_dev_ruby_token(requirement)
      min_ruby = minimum_ruby_token(requirement)
      return "" if min_ruby.empty?

      [Gem::Version.new(min_ruby), Gem::Version.new("2.3")].max.to_s
    rescue ArgumentError
      "2.3"
    end

    def gem_major_token(version)
      Gem::Version.new(version.to_s).segments.first.to_s
    rescue ArgumentError
      "0"
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

    def copyright_facts(project_root, config)
      lines = git_copyright_lines(project_root, copyright_machine_users(config))
      compact_hash(lines: lines)
    end

    def copyright_machine_users(config)
      copyright = config["copyright"].is_a?(Hash) ? config["copyright"] : {}
      Array(copyright["machine_users"]).map { |user| user.to_s.downcase.strip }.reject(&:empty?)
    end

    def git_copyright_lines(project_root, machine_users)
      files = git_capture(project_root, "ls-files", "-z")
      return [] if files.to_s.empty?

      author_map = Hash.new { |hash, email| hash[email] = { name: nil, years: [], email: email } }
      files.split("\0").reject(&:empty?).each do |relative_path|
        next unless File.exist?(File.join(project_root, relative_path))

        parse_blame_porcelain(git_capture(project_root, "blame", "--porcelain", "--", relative_path), author_map)
      rescue ArgumentError
        next
      end
      resolve_uncommitted_author!(project_root, author_map)
      author_map.values
        .reject { |entry| copyright_bot_entry?(entry) }
        .reject { |entry| copyright_machine_user_entry?(entry, machine_users) }
        .reject { |entry| entry[:name].to_s.strip.empty? || entry[:years].empty? }
        .sort_by { |entry| [entry[:years].map(&:to_i).min, entry[:name].to_s.downcase] }
        .map { |entry| "Copyright (c) #{format_copyright_years(entry[:years])} #{entry[:name]}" }
    rescue ArgumentError
      []
    end

    def git_capture(project_root, *args)
      output = IO.popen(["git", "-C", project_root.to_s, *args], err: File::NULL, &:read)
      raise ArgumentError, "git #{args.join(" ")} failed" unless $CHILD_STATUS&.success?

      output.to_s
    end

    def parse_blame_porcelain(output, author_map)
      commit_meta = {}
      current_sha = nil
      current_name = nil
      current_email = nil
      current_time = nil
      output.to_s.each_line do |raw_line|
        line = raw_line.chomp
        if line.match?(/\A[0-9a-f]{40}\s/)
          current_sha = line[0, 40]
          meta = commit_meta[current_sha]
          current_name = meta && meta[:name]
          current_email = meta && meta[:email]
          current_time = meta && meta[:time]
        elsif line.start_with?("author ") && !commit_meta.key?(current_sha.to_s)
          current_name = line[7..].strip
        elsif line.start_with?("author-mail ") && !commit_meta.key?(current_sha.to_s)
          current_email = line[12..].strip.gsub(/[<>]/, "")
        elsif line.start_with?("author-time ") && !commit_meta.key?(current_sha.to_s)
          current_time = line[12..].strip.to_i
        elsif line.start_with?("filename ")
          next unless current_sha && current_email

          commit_meta[current_sha] ||= { name: current_name, email: current_email, time: current_time }
          year = current_time && current_time.positive? ? Time.at(current_time).utc.year.to_s : Time.now.utc.year.to_s
          author_map[current_email][:name] ||= current_name
          author_map[current_email][:years] << year
        end
      end
    end

    def resolve_uncommitted_author!(project_root, author_map)
      uncommitted = author_map.delete(NOT_COMMITTED_EMAIL)
      return unless uncommitted && !uncommitted[:years].empty?

      name = git_capture(project_root, "config", "user.name").strip
      email = git_capture(project_root, "config", "user.email").strip
      return if email.empty?

      author_map[email][:name] ||= name
      author_map[email][:years].concat(uncommitted[:years])
    rescue ArgumentError
      nil
    end

    def copyright_bot_entry?(entry)
      entry[:name].to_s.match?(BOT_NAME_SUFFIX) || entry[:email].to_s.match?(BOT_EMAIL_PATTERN)
    end

    def copyright_machine_user_entry?(entry, machine_users)
      return false if machine_users.empty?

      machine_users.include?(entry[:name].to_s.downcase.strip) ||
        machine_users.include?(entry[:email].to_s.downcase.strip)
    end

    def format_copyright_years(years)
      sorted = Array(years).map(&:to_i).reject(&:zero?).sort.uniq
      return Time.now.utc.year.to_s if sorted.empty?
      return sorted.first.to_s if sorted.one?

      runs = []
      run = [sorted.first]
      sorted[1..].to_a.each do |year|
        if year == run.last + 1
          run << year
        else
          runs << run
          run = [year]
        end
      end
      runs << run
      runs.map { |span| span.one? ? span.first.to_s : "#{span.first}-#{span.last}" }.join(", ")
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

    def project_runtime_facts(config, env, package_name:, source_url:, author_domain:, min_ruby:, version:)
      run_timestamp = Time.now
      compact_hash(
        freeze_token: config.dig("defaults", "freeze_token").to_s.empty? ? "kettle-jem" : config.dig("defaults", "freeze_token").to_s,
        kettle_jem_version: VERSION,
        template_run_date: run_timestamp.strftime("%Y-%m-%d"),
        template_run_year: run_timestamp.year.to_s,
        kettle_dev_gem: "kettle-dev",
        yard_host: "#{package_name.to_s.tr("_", "-")}.#{author_domain.to_s.empty? ? "example.com" : author_domain}",
        project_emoji: preferred_template_token_value(nil, config["project_emoji"], env, "KJ_PROJECT_EMOJI").to_s,
        min_divergence_threshold: preferred_template_token_value(nil, config["min_divergence_threshold"], env, "KJ_MIN_DIVERGENCE_THRESHOLD").to_s,
        min_dev_ruby: minimum_dev_ruby_token(min_ruby),
        version: version.to_s,
        github_org: github_org_from_url(source_url).to_s
      )
    end

    def project_runtime_template_tokens(project_runtime)
      {
        "KJ|FREEZE_TOKEN" => project_runtime[:freeze_token].to_s,
        "KJ|KETTLE_JEM_VERSION" => project_runtime[:kettle_jem_version].to_s,
        "KJ|TEMPLATE_RUN_DATE" => project_runtime[:template_run_date].to_s,
        "KJ|TEMPLATE_RUN_YEAR" => project_runtime[:template_run_year].to_s,
        "KJ|KETTLE_DEV_GEM" => project_runtime[:kettle_dev_gem].to_s,
        "KJ|YARD_HOST" => project_runtime[:yard_host].to_s,
        "KJ|PROJECT_EMOJI" => project_runtime[:project_emoji].to_s,
        "KJ|MIN_DIVERGENCE_THRESHOLD" => project_runtime[:min_divergence_threshold].to_s,
      }
    end

    def shield_token(value)
      value.to_s.gsub("-", "--").gsub("_", "__").gsub("::", "%3A%3A").tr(" ", "_")
    end

    def github_org_from_url(url)
      match = url.to_s.match(%r{\Ahttps?://github\.com/([^/]+)/})
      match && match[1]
    end

    def concrete_github_url(url)
      github_org_from_url(url) ? url.to_s : nil
    end

    def readme_logo_facts(config, package_name:, github_org:)
      entries = readme_top_logo_entries(config, org: github_org.to_s, gem_name: package_name.to_s)
      compact_hash(
        top_logo_mode: readme_top_logo_mode(config),
        top_logo_row: [README_STATIC_TOP_LOGO_ROW, readme_top_logo_row(entries)].reject(&:empty?).join(" "),
        top_logo_refs: [README_STATIC_TOP_LOGO_REFS, readme_top_logo_refs(entries)].reject(&:empty?).join("\n")
      )
    end

    def readme_top_logo_mode(config)
      raw_config = config.is_a?(Hash) ? config["readme"] : nil
      readme_config = raw_config.is_a?(Hash) ? raw_config : {}
      normalized = readme_config["top_logo_mode"].to_s.strip.downcase.tr("-", "_")
      return README_TOP_LOGO_MODE_DEFAULT if normalized.empty?
      return normalized if README_TOP_LOGO_MODES.include?(normalized)

      README_TOP_LOGO_MODE_DEFAULT
    end

    def readme_top_logo_entries(config, org:, gem_name:)
      configured = configured_readme_top_logo_entries(config, org: org, gem_name: gem_name)
      return configured if configured

      readme_top_logo_mode_entries(readme_top_logo_mode(config), org: org, gem_name: gem_name)
    end

    def configured_readme_top_logo_entries(config, org:, gem_name:)
      readme_config = config.is_a?(Hash) && config["readme"].is_a?(Hash) ? config["readme"] : {}
      logo_row = readme_config["logo_row"]
      return nil unless logo_row.is_a?(Hash)
      return [] if falsey_config?(logo_row["enabled"])

      logos = Array(logo_row["logos"]).first(3)
      return [] if logos.empty?

      logos.filter_map do |logo|
        readme_top_logo_entry_from_config(logo, org: org, gem_name: gem_name)
      end.uniq { |entry| [entry[:image_ref], entry[:link_ref], entry[:image_url], entry[:href]] }
    end

    def readme_top_logo_entry_from_config(logo, org:, gem_name:)
      return nil unless logo.is_a?(Hash)

      type = logo["type"].to_s.strip.downcase.tr("-", "_")
      return nil unless README_TOP_LOGO_TYPES.include?(type)

      slug = logo["slug"].to_s.strip
      slug = default_readme_top_logo_slug(type, org: org, gem_name: gem_name) if slug.empty?
      return nil if slug.empty?

      alt = logo["alt"].to_s.strip
      alt = readme_top_logo_default_alt(type, slug) if alt.empty?
      href = logo["href"].to_s.strip
      href = default_readme_top_logo_href(type, slug: slug, org: org, gem_name: gem_name) if href.empty?
      ref_slug = slug.tr("/", "-")
      {
        label: alt.sub(/\s+logo\z/i, ""),
        image_ref: "#{ref_slug}-i",
        link_ref: ref_slug,
        image_url: "#{LOGOS_GALTZO_BASE_URL}/#{slug}/avatar-192px.svg",
        href: href,
      }
    end

    def default_readme_top_logo_slug(type, org:, gem_name:)
      case type
      when "language"
        "ruby-lang"
      when "org"
        org.to_s
      when "project"
        [org, gem_name].reject(&:empty?).join("/")
      else
        ""
      end
    end

    def readme_top_logo_default_alt(type, slug)
      label = slug.split("/").last.to_s
      case type
      when "language"
        "#{label} language"
      when "org"
        "#{label} organization"
      when "project"
        "#{label} project"
      else
        "#{label} affiliated project"
      end
    end

    def default_readme_top_logo_href(type, slug:, org:, gem_name:)
      case type
      when "language"
        slug == "ruby-lang" ? "https://www.ruby-lang.org/" : "#{LOGOS_GALTZO_BASE_URL}/#{slug}/"
      when "org"
        org.to_s.empty? ? "#{LOGOS_GALTZO_BASE_URL}/#{slug}/" : "https://github.com/#{org}"
      when "project"
        org.to_s.empty? || gem_name.to_s.empty? ? "#{LOGOS_GALTZO_BASE_URL}/#{slug}/" : "https://github.com/#{org}/#{gem_name}"
      else
        "#{LOGOS_GALTZO_BASE_URL}/#{slug}/"
      end
    end

    def readme_top_logo_mode_entries(mode, org:, gem_name:)
      return [] if org.empty?

      entries = []
      if mode == "org" || mode == "org_and_project"
        entries << {
          label: org,
          image_ref: "#{org}-i",
          link_ref: org,
          image_url: "#{LOGOS_GALTZO_BASE_URL}/#{org}/avatar-192px.svg",
          href: "https://github.com/#{org}",
        }
      end
      if mode == "project" || mode == "org_and_project"
        entries << {
          label: gem_name,
          image_ref: "#{gem_name}-i",
          link_ref: gem_name,
          image_url: "#{LOGOS_GALTZO_BASE_URL}/#{org}/#{gem_name}/avatar-192px.svg",
          href: "https://github.com/#{org}/#{gem_name}",
        }
      end
      entries.uniq { |entry| [entry[:image_ref], entry[:link_ref], entry[:image_url], entry[:href]] }
    end

    def readme_top_logo_row(entries)
      entries.map do |entry|
        "[![#{entry[:label]} Logo by Aboling0, CC BY-SA 4.0][🖼️#{entry[:image_ref]}]][🖼️#{entry[:link_ref]}]"
      end.join(" ")
    end

    def readme_top_logo_refs(entries)
      entries.flat_map do |entry|
        [
          "[🖼️#{entry[:image_ref]}]: #{entry[:image_url]}",
          "[🖼️#{entry[:link_ref]}]: #{entry[:href]}",
        ]
      end.join("\n")
    end

    def readme_logo_template_tokens(readme_logo)
      {
        "KJ|README:TOP_LOGO_ROW" => readme_logo[:top_logo_row].to_s,
        "KJ|README:TOP_LOGO_REFS" => readme_logo[:top_logo_refs].to_s,
      }
    end

    def rubocop_template_tokens(min_ruby)
      constraint, gem_name = rubocop_tokens_for(min_ruby_version(min_ruby))
      {
        "KJ|RUBOCOP_LTS_CONSTRAINT" => constraint,
        "KJ|RUBOCOP_RUBY_GEM" => gem_name,
      }
    end

    def rubocop_tokens_for(min_ruby)
      fallback = RUBOCOP_VERSION_MAP.first
      selected = nil
      RUBOCOP_VERSION_MAP.reverse_each do |minimum, constraint|
        next unless min_ruby && min_ruby >= minimum

        selected = [minimum, constraint]
        break
      end
      selected ||= fallback
      [selected[1], "rubocop-ruby#{selected[0].segments.join("_")}"]
    end

    def min_ruby_version(requirement)
      token = minimum_ruby_token(requirement)
      return nil if token.empty?

      Gem::Version.new(token)
    rescue ArgumentError
      nil
    end

    def license_facts(config, gemspec_licenses, author: {}, author_email: nil, copyright: {})
      licenses = resolved_licenses(config, gemspec_licenses)
      primary = licenses.first
      compat_category = license_compat_category(licenses)
      copyright_prefix = polyform_licenses?(licenses) ? "Required Notice: " : ""
      copyright_lines = Array(copyright[:lines])
      compact_hash(
        spdx: licenses,
        expression: licenses.join(" OR "),
        primary_spdx: primary,
        license_md_content: license_md_content(licenses, author_email: author_email),
        readme_license_intro: readme_license_intro(licenses, author_email: author_email),
        readme_license_badge: license_badge(primary),
        readme_license_compat_badge: license_compat_badge(compat_category),
        readme_license_refs: readme_license_refs(primary, compat_category),
        license_copyright_notice: license_copyright_notice(copyright_lines, copyright_prefix, author),
        readme_copyright_notice: readme_copyright_notice(copyright_lines, copyright_prefix),
        copyright_prefix: copyright_prefix
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
        "KJ|LICENSE_COPYRIGHT_NOTICE" => license[:license_copyright_notice].to_s,
        "KJ|README:COPYRIGHT_NOTICE" => license[:readme_copyright_notice].to_s,
        "KJ|COPYRIGHT_PREFIX" => license[:copyright_prefix].to_s,
      }
    end

    def license_copyright_notice(copyright_lines, copyright_prefix, author)
      lines = Array(copyright_lines).map { |line| "#{copyright_prefix}#{line}" }
      return "## Copyright Notice\n\n#{lines.join("\n")}" unless lines.empty?

      "#{copyright_prefix}Copyright (c) #{Time.now.utc.year} #{[author[:given_names], author[:family_names]].compact.join(" ").strip}"
    end

    def readme_copyright_notice(copyright_lines, copyright_prefix)
      lines = Array(copyright_lines).map { |line| "- #{copyright_prefix}#{line}" }
      return "See [LICENSE.md][#{paperclip_ref(:license)}] for the official copyright notice." if lines.empty?

      <<~MARKDOWN.chomp
        See [LICENSE.md][#{paperclip_ref(:license)}] for the official copyright notice.

        <details markdown="1">
        <summary>Copyright holders</summary>

        #{lines.join("\n")}

        </details>
      MARKDOWN
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

    def resolve_template_tokens(content, tokens, scan_unresolved: true)
      resolver = Token::Resolver::Resolve.new(on_missing: :keep)
      document = Token::Resolver::Document.new(content.to_s, config: TEMPLATE_TOKEN_CONFIG)
      resolved = resolver.resolve(document, stringify_template_tokens(tokens))
      return resolved unless scan_unresolved

      unresolved = Token::Resolver::Document.new(resolved, config: TEMPLATE_TOKEN_CONFIG).token_keys.grep(/\AKJ\|/).sort
      return resolved if unresolved.empty?

      raise ArgumentError, "unresolved kettle-jem template tokens: #{unresolved.map { |token| "{#{token}}" }.join(", ")}"
    end

    def readme_style_facts(project_root, config, license)
      readme = config["readme"].is_a?(Hash) ? config["readme"] : {}
      conditional = readme["conditional_sections"].is_a?(Hash) ? readme["conditional_sections"] : {}
      disabled_integrations = readme_disabled_integrations(readme)
      missing_integrations = README_INTEGRATIONS.reject do |integration|
        disabled_integrations.include?(integration) || readme_integration_configured?(project_root, integration)
      end
      omitted_sections = []
      security_enabled = File.exist?(File.join(project_root, "SECURITY.md"))
      floss_funding_enabled = readme_floss_funding_enabled?(license, conditional["floss_funding"])
      omitted_sections << "security" unless security_enabled
      omitted_sections << "floss_funding" unless floss_funding_enabled
      section_partials = readme_section_partials(project_root, config, readme)
      compact_hash(
        profile: "slice-740-kettle-readme-style-profile",
        security_enabled: security_enabled,
        floss_funding_enabled: floss_funding_enabled,
        omitted_sections: omitted_sections,
        disabled_integrations: disabled_integrations,
        missing_integrations: missing_integrations,
        section_partials: section_partials,
      )
    end

    def readme_section_partials(project_root, config, readme)
      configured = readme["section_partials"]
      return {} unless configured.is_a?(Hash)

      root = template_root(project_root, config["templates"].is_a?(Hash) ? config["templates"] : {})
      configured.each_with_object({}) do |(section, source), result|
        normalized = normalize_readme_section_key(section)
        next if normalized.empty?

        source_path = source.to_s
        next if source_path.empty?

        selected = preferred_template_source(root.fetch(:path), source_path)
        next unless selected

        result[normalized] = {
          configured_source: source_path,
          selected_source: template_source_display_path(root, selected),
          source_relative_path: selected,
          source_root: root.fetch(:kind),
          content: File.read(File.join(root.fetch(:path), selected)),
        }
      end
    end

    def normalize_readme_section_key(section)
      normalize_readme_heading(section.to_s.tr("_-", " "))
    end

    def readme_floss_funding_enabled?(license, config_value)
      return false if falsey_config?(config_value)
      return true if %w[true yes 1 always enabled].include?(config_value.to_s.strip.downcase)

      Array(license[:spdx]).map(&:to_s).include?("MIT")
    end

    def readme_disabled_integrations(readme)
      disabled = []
      integrations = readme["integrations"].is_a?(Hash) ? readme["integrations"] : {}
      badges = readme["badges"].is_a?(Hash) ? readme["badges"] : {}
      integrations.each do |name, value|
        disabled << name.to_s if falsey_config?(value)
      end
      disabled.concat(Array(badges["disabled"]).map(&:to_s))
      disabled.map { |name| name.tr("_", "-").downcase }.map { |name| name == "code-ql" ? "codeql" : name }.uniq & README_INTEGRATIONS
    end

    def readme_integration_configured?(project_root, integration)
      case integration
      when "codecov"
        File.exist?(File.join(project_root, ".codecov.yml")) ||
          File.exist?(File.join(project_root, "codecov.yml")) ||
          github_workflows_include?(project_root, "codecov/codecov-action")
      when "coveralls"
        File.exist?(File.join(project_root, ".coveralls.yml")) ||
          github_workflows_include?(project_root, "coverallsapp/github-action")
      when "qlty"
        File.exist?(File.join(project_root, ".qlty/qlty.toml")) ||
          File.exist?(File.join(project_root, ".qlty.yml")) ||
          github_workflows_include?(project_root, "qltysh/qlty-action")
      when "codeql"
        File.exist?(File.join(project_root, ".github/workflows/codeql.yml")) ||
          File.exist?(File.join(project_root, ".github/workflows/codeql-analysis.yml")) ||
          github_workflows_include?(project_root, "github/codeql-action")
      else
        false
      end
    end

    def github_workflows_include?(project_root, needle)
      Dir.glob(File.join(project_root, ".github/workflows/*.{yml,yaml}")).any? do |path|
        File.read(path).include?(needle)
      rescue Errno::ENOENT
        false
      end
    end

    def unresolved_template_scan?(recipe)
      return false if recipe.fetch(:target_path).to_s == ".kettle-jem.yml"
      return false if recipe.dig(:template_preference, :skip_unresolved_scan)

      true
    end

    def stringify_template_tokens(tokens)
      tokens.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end

    def falsey_config?(value)
      %w[false no 0].include?(value.to_s.strip.downcase)
    end

    def merge_readme_template(template_content:, destination_content:, preserve_config: {})
      return template_content if destination_content.to_s.strip.empty?

      preserved = preserve_readme_sections(template_content, destination_content, preserve_config)
      preserve_readme_h1(preserved, destination_content)
    end

    def preserve_readme_sections(template_content, destination_content, preserve_config)
      template_sections = markdown_sections(template_content)
      destination_sections = markdown_sections(destination_content)
      destination_lookup = destination_sections.to_h { |section| [section.fetch(:base), section] }
      preserve_targets = readme_preserve_targets(template_sections, destination_lookup, preserve_config)
      return template_content if preserve_targets.empty?

      lines = template_content.split("\n", -1)
      template_sections.reverse_each do |section|
        next unless preserve_targets.include?(section.fetch(:base))

        destination_section = destination_lookup[section.fetch(:base)] ||
          aliased_readme_destination_section(section.fetch(:base), destination_lookup, preserve_config)
        next unless destination_section

        replacement = "#{section.fetch(:heading)}\n#{destination_section.fetch(:body)}".split("\n", -1)
        lines[section.fetch(:start)..section.fetch(:end)] = replacement
      end
      lines.join("\n")
    end

    def preserve_readme_h1(merged_content, destination_content)
      merged_h1 = markdown_sections(merged_content).find { |section| section.fetch(:level) == 1 }
      destination_h1 = markdown_sections(destination_content).find { |section| section.fetch(:level) == 1 }
      return merged_content unless merged_h1 && destination_h1
      return merged_content if semantic_readme_heading(destination_h1.fetch(:heading_text)) == semantic_readme_heading(merged_h1.fetch(:heading_text))

      lines = merged_content.split("\n", -1)
      lines[merged_h1.fetch(:start)] = destination_h1.fetch(:heading)
      lines.join("\n")
    end

    def markdown_sections(content)
      lines = content.to_s.split("\n", -1)
      headings = []
      in_fence = false
      fence_marker = nil
      lines.each_with_index do |line, index|
        stripped = line.lstrip
        if in_fence
          if stripped.match?(/\A#{Regexp.escape(fence_marker)}\s*\z/)
            in_fence = false
            fence_marker = nil
          end
          next
        end
        if (fence = stripped.match(/\A(`{3,}|~{3,})/))
          in_fence = true
          fence_marker = fence[1]
          next
        end
        next unless (heading = line.match(/\A(\#{1,6})\s+(.+?)\s*#*\s*\z/))

        headings << {
          start: index,
          level: heading[1].length,
          heading: line,
          heading_text: heading[2],
          base: normalize_readme_heading(heading[2]),
        }
      end

      headings.each_with_index.map do |heading, index|
        following = headings[(index + 1)..].to_a.find { |candidate| candidate.fetch(:level) <= heading.fetch(:level) }
        branch_end = following ? following.fetch(:start) - 1 : lines.length - 1
        body = (lines[(heading.fetch(:start) + 1)..branch_end] || []).join("\n")
        heading.merge(end: branch_end, body: body)
      end
    end

    def readme_preserve_targets(template_sections, destination_lookup, preserve_config)
      sections = if preserve_config.key?(:sections)
        Array(preserve_config[:sections]).map { |section| normalize_readme_heading(section) }
      else
        README_DEFAULT_PRESERVE_SECTIONS.dup
      end
      patterns = if preserve_config.key?(:patterns)
        Array(preserve_config[:patterns]).map { |pattern| pattern.to_s.strip.downcase }
      else
        README_DEFAULT_PRESERVE_PATTERNS.dup
      end
      aliases = preserve_config[:aliases] || README_SECTION_ALIASES
      targets = sections.dup
      template_sections.each do |section|
        base = section.fetch(:base)
        targets << base if patterns.any? { |pattern| File.fnmatch?(pattern, base, File::FNM_PATHNAME) }
      end
      aliases.each do |from, to|
        targets << to if destination_lookup.key?(from) && targets.include?(to)
      end
      targets.uniq
    end

    def aliased_readme_destination_section(template_base, destination_lookup, preserve_config)
      aliases = preserve_config[:aliases] || README_SECTION_ALIASES
      aliases.each do |from, to|
        return destination_lookup[from] if to == template_base && destination_lookup.key?(from)
      end
      nil
    end

    def readme_preserve_config(config)
      readme = config["readme"]
      return {} unless readme.is_a?(Hash)

      result = {}
      result[:sections] = Array(readme["preserve_sections"]) if readme.key?("preserve_sections")
      result[:patterns] = Array(readme["preserve_patterns"]) if readme.key?("preserve_patterns")
      if readme["section_aliases"].is_a?(Hash)
        result[:aliases] = README_SECTION_ALIASES.merge(
          readme["section_aliases"].transform_keys { |key| normalize_readme_heading(key) }
                                   .transform_values { |value| normalize_readme_heading(value) }
        )
      end
      result
    end

    def normalize_readme_heading(text)
      strip_readme_heading_adornment(text).strip.downcase
    end

    def semantic_readme_heading(text)
      normalize_readme_heading(text)
    end

    def strip_readme_heading_adornment(text)
      text.to_s.sub(/\A(?:\d\uFE0F?\u20E3|[^[:alnum:][:space:]])+[ \t]*/u, "")
    end

    def template_source_preferences(project_root, config, opencollective_disabled: false)
      templates = config["templates"]
      return [] unless templates.is_a?(Hash)

      root = template_root(project_root, templates)
      entries = template_entries(project_root, root, templates)
      return [] if entries.empty?

      apply_templates = templates["apply"] == true
      entries.filter_map do |entry|
        template_source_preference(
          project_root,
          root,
          entry,
          config,
          opencollective_disabled: opencollective_disabled,
          apply_templates: apply_templates
        )
      end
    end

    def template_entries(project_root, root, templates)
      return templates["entries"] if templates["entries"].is_a?(Array)
      return [] if templates.key?("entries")

      template_inventory_entries(project_root, root.fetch(:path))
    end

    def template_inventory_entries(project_root, template_root_path)
      logical_paths = []
      Find.find(template_root_path) do |path|
        next if File.directory?(path)

        relative_path = path.delete_prefix("#{template_root_path}/")
        logical_path = relative_path
          .sub(/\.no-osc\.example\z/, "")
          .sub(/\.example\z/, "")
        next if logical_path.start_with?("readme/partials/")

        logical_paths << logical_path unless logical_path.empty?
      end

      logical_paths.uniq.sort.map do |logical_path|
        target_path = template_inventory_target_path(project_root, logical_path)
        if target_path == logical_path
          logical_path
        else
          { "source" => logical_path, "target" => target_path }
        end
      end
    end

    def template_inventory_target_path(project_root, logical_path)
      return ".env.local.example" if logical_path == ".env.local"

      if logical_path.end_with?(".gemspec")
        existing_gemspec = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
        return File.basename(existing_gemspec) if existing_gemspec
      end

      logical_path
    end

    def copy_only_when_missing_template_path?(relative_path)
      COPY_ONLY_WHEN_MISSING_TEMPLATE_PATHS.include?(relative_path.to_s)
    end

    def kettle_config_bootstrap_facts(project_root, env)
      return if File.exist?(File.join(project_root, ".kettle-jem.yml"))

      selected_source = preferred_template_source(PACKAGED_TEMPLATE_ROOT, ".kettle-jem.yml")
      return unless selected_source

      {
        template_preference: {
          target_path: ".kettle-jem.yml",
          configured_source: ".kettle-jem.yml",
          selected_source: selected_source,
          source_relative_path: selected_source,
          source_root: "packaged",
          source_root_path: PACKAGED_TEMPLATE_ROOT,
          selection_reason: template_source_selection_reason(".kettle-jem.yml", selected_source),
          apply: true,
        },
        min_divergence_threshold: preferred_template_token_value(nil, nil, env, "KJ_MIN_DIVERGENCE_THRESHOLD").to_s,
      }
    end

    def kettle_config_bootstrap_recipe(bootstrap)
      recipe = recipe_entry(
        "kettle_config_bootstrap",
        ".kettle-jem.yml",
        "yaml",
        "supplied_kettle_config_bootstrap",
        facts: %w[kettle_config_bootstrap]
      )
      recipe[:template_preference] = bootstrap.fetch(:template_preference)
      recipe[:template_tokens] = {
        "KJ|MIN_DIVERGENCE_THRESHOLD" => bootstrap.fetch(:min_divergence_threshold).to_s,
      }
      recipe
    end

    def template_source_preference(project_root, template_root, entry, config, opencollective_disabled: false, apply_templates: false)
      source_path, target_path = template_entry_paths(entry)
      return nil if source_path.to_s.empty? || target_path.to_s.empty?

      selected_source = preferred_template_source(template_root.fetch(:path), source_path, opencollective_disabled: opencollective_disabled)
      return nil unless selected_source

      strategy_config = template_strategy_config(config, target_path)
      preference = {
        target_path: target_path,
        configured_source: source_path,
        selected_source: template_source_display_path(template_root, selected_source),
        selection_reason: template_source_selection_reason(source_path, template_source_display_path(template_root, selected_source)),
        apply: template_entry_apply?(entry, apply_templates),
      }
      preference[:strategy] = strategy_config.fetch(:strategy).to_s if strategy_config
      preference[:file_type] = strategy_config.fetch(:file_type).to_s if strategy_config&.key?(:file_type)
      preference[:method_move_policy] = strategy_config.fetch(:method_move_policy).to_s if strategy_config&.key?(:method_move_policy)
      if copy_only_when_missing_template_path?(target_path) && File.exist?(File.join(project_root, target_path))
        preference[:strategy] = "keep_destination"
        preference[:policy] = "copy_only_when_missing"
      end
      preserve_config = readme_preserve_config(config)
      preference[:readme_preserve_config] = preserve_config if target_path == "README.md" && !preserve_config.empty?
      if template_root.fetch(:kind) == "packaged"
        preference[:source_relative_path] = selected_source
        preference[:source_root] = template_root.fetch(:kind)
        preference[:source_root_path] = template_root.fetch(:path)
      end
      preference
    end

    def template_legacy_destination_cleanups(project_root, preferences)
      preferences.filter_map do |preference|
        canonical_path = preference.fetch(:target_path)
        legacy_path = LEGACY_DESTINATION_PATHS[canonical_path]
        next unless legacy_path
        next unless File.exist?(File.join(project_root, legacy_path))
        next if preference[:strategy] == "keep_destination" && !File.exist?(File.join(project_root, canonical_path))

        {
          canonical_path: canonical_path,
          legacy_path: legacy_path,
        }
      end
    end

    def template_strategy_config(config, target_path)
      template_file_strategy_config(config, target_path) || template_pattern_strategy_config(config, target_path)
    end

    def template_file_strategy_config(config, target_path)
      files = config["files"]
      return unless files.is_a?(Hash)

      current = files
      target_path.to_s.delete_prefix("./").split("/").each do |part|
        return unless current.is_a?(Hash) && current.key?(part)

        current = current[part]
      end
      return unless current.is_a?(Hash) && current.key?("strategy")

      template_strategy_entry(config, nil, current)
    end

    def template_pattern_strategy_config(config, target_path)
      patterns = config["patterns"]
      return unless patterns.is_a?(Array)

      match = patterns.find do |entry|
        entry.is_a?(Hash) &&
          File.fnmatch?(entry["path"].to_s, target_path.to_s, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
      end
      return unless match

      template_strategy_entry(config, match["path"].to_s, match)
    end

    def template_strategy_entry(config, path, entry)
      strategy = entry["strategy"].to_s.strip.downcase.to_sym
      raise ArgumentError, "unknown kettle-jem template strategy: #{entry["strategy"]}" unless SUPPORTED_TEMPLATE_STRATEGIES.include?(strategy)

      result = { strategy: strategy }
      result[:path] = path if path
      result[:skip_unresolved_scan] = true if entry["skip_unresolved_scan"]
      if entry.key?("file_type")
        file_type = entry["file_type"].to_s.strip.downcase.tr("-", "_").to_sym
        raise ArgumentError, "unknown kettle-jem template file_type: #{entry["file_type"]}" unless SUPPORTED_TEMPLATE_FILE_TYPES.include?(file_type)

        result[:file_type] = file_type
      end
      if strategy == :merge
        defaults = config["defaults"].is_a?(Hash) ? config["defaults"] : {}
        result[:preference] = (entry.key?("preference") ? entry["preference"] : defaults["preference"]).to_s if entry.key?("preference") || defaults.key?("preference")
        if entry.key?("add_template_only_nodes") || defaults.key?("add_template_only_nodes")
          result[:add_template_only_nodes] = entry.key?("add_template_only_nodes") ? entry["add_template_only_nodes"] : defaults["add_template_only_nodes"]
        end
        result[:freeze_token] = (entry.key?("freeze_token") ? entry["freeze_token"] : defaults["freeze_token"]).to_s if entry.key?("freeze_token") || defaults.key?("freeze_token")
        if entry.key?("method_move_policy") || defaults.key?("method_move_policy")
          policy = (entry.key?("method_move_policy") ? entry["method_move_policy"] : defaults["method_move_policy"]).to_s
          raise ArgumentError, "unknown kettle-jem Ruby method_move_policy: #{policy}" unless SUPPORTED_RUBY_METHOD_MOVE_POLICIES.include?(policy)

          result[:method_move_policy] = policy
        end
      end
      result
    end

    def template_root(project_root, templates)
      configured_root = templates["root"].to_s
      if configured_root.empty?
        local_root = File.join(project_root, "template")
        return { kind: "project", path: local_root, display_prefix: "template" } if Dir.exist?(local_root)

        return { kind: "packaged", path: PACKAGED_TEMPLATE_ROOT }
      end

      return { kind: "packaged", path: PACKAGED_TEMPLATE_ROOT } if configured_root == "packaged"

      path = configured_root.start_with?("/") ? configured_root : File.join(project_root, configured_root)
      { kind: "project", path: path, display_prefix: configured_root }
    end

    def template_source_display_path(template_root, selected_source)
      prefix = template_root[:display_prefix].to_s
      return selected_source if prefix.empty?

      File.join(prefix, selected_source)
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

    def preferred_template_source(template_root, configured_source, opencollective_disabled: false)
      base = configured_source.sub(/\.example\z/, "")
      candidates = []
      candidates << "#{base}.no-osc.example" if opencollective_disabled
      candidates << "#{base}.example"
      candidates << configured_source
      candidates.find { |relative_path| File.exist?(File.join(template_root, relative_path)) }
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
          unless rakefile_template_default_task?(lines, index)
            end_index = rakefile_block_end(lines, index)
            selectors << rakefile_selector("rakefile_scaffold_task_default", index + 1, end_index + 1,
              "wrapper_selected_scaffold_task")
            index = end_index + 1
            next
          end
        end
        index += 1
      end
      selectors
    end

    def rakefile_template_default_task?(lines, task_index)
      cursor = task_index - 1
      cursor -= 1 while cursor >= 0 && lines[cursor].strip.empty?
      return false unless cursor >= 0

      lines[cursor].strip == 'desc "Default tasks aggregator"'
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
