# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Kettle::Jem do
  def json_ready(value)
    JSON.parse(JSON.generate(value), symbolize_names: true)
  end

  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path.to_s)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def project_files(root, paths)
    paths.to_h do |relative_path|
      path = File.join(root, relative_path)
      [relative_path.to_sym, File.exist?(path) ? File.read(path) : nil]
    end
  end

  let(:fixture_path) { Pathname(__dir__).join("fixtures/thin_slice.json") }
  let(:fixture) { JSON.parse(fixture_path.read, symbolize_names: true) }
  let(:contract_path) do
    Pathname(__dir__).join("../../../../fixtures/packaging/thin-slice-contract.json").expand_path
  end
  let(:contract) { JSON.parse(contract_path.read, symbolize_names: true) }

  it "plans and applies the RubyGems thin vertical slice" do
    expected_recipe_names = contract.fetch(:canonical_recipes).map { |recipe| recipe.fetch(:name).to_s }
    expect(contract.fetch(:validated_ecosystems)).to include(fixture.fetch(:ecosystem))
    expect(fixture.fetch(:expected).fetch(:facts).keys).to include(
      *contract.fetch(:required_fact_groups).map(&:to_sym),
      contract.fetch(:ecosystem_fact_groups).fetch(:rubygems).to_sym
    )

    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-thin-slice", tmp_root) do |root|
      write_tree(root, fixture.fetch(:inputs).fetch(:files))

      plan = described_class.plan_project(root, env: {})
      expect(json_ready(plan[:facts])).to eq(json_ready(fixture.fetch(:expected).fetch(:facts)))
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe[:name] }
      expect(recipe_names.take(expected_recipe_names.length)).to eq(expected_recipe_names)
      expect(recipe_names).to include("github_funding_yml")
      expect(recipe_names).to include("github_actions_ci")
      expect(recipe_names).to include("github_actions_framework_ci")
      expect(recipe_names).to include(a_string_starting_with("github_actions_obsolete_workflow_cleanup_"))
      expect(recipe_names).to include("rakefile_scaffold_cleanup")
      expect(recipe_names).to include(a_string_starting_with("github_actions_workflow_snippets_"))
      expect(plan[:changed_files]).to eq(fixture.fetch(:expected).fetch(:changed_files))
      expect(plan[:recipe_reports].map { |report| report[:request_envelope][:kind] }.uniq).to eq(
        [contract.fetch(:report_contract).fetch(:request_envelope_kind)]
      )
      expect(plan[:recipe_reports].map { |report| report[:report_envelope][:kind] }.uniq).to eq(
        [contract.fetch(:report_contract).fetch(:report_envelope_kind)]
      )
      rakefile_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "rakefile_scaffold_cleanup" }
      expect(rakefile_report.dig(:request_envelope, :request, :runtime_context, :delete_selectors).length).to eq(4)
      expect(rakefile_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :deleted_ranges)).to eq(4)
      expect(rakefile_report.fetch(:final_content)).to include("task :custom")
      expect(rakefile_report.fetch(:final_content)).not_to include("bundler/gem_tasks")
      expect(rakefile_report.fetch(:final_content)).not_to include("RSpec::Core::RakeTask")
      ci_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_actions_ci" }
      expect(ci_report.dig(:request_envelope, :request, :provider_family)).to eq("yaml")
      expect(ci_report.fetch(:final_content)).to include("ruby/setup-ruby@")
      expect(ci_report.fetch(:final_content)).to include("- \"3.2\"")
      funding_yml_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_funding_yml" }
      expect(funding_yml_report.fetch(:final_content)).to include("tidelift: rubygems/example")
      expect(funding_yml_report.fetch(:final_content)).to include("open_collective: example")
      framework_ci_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_actions_framework_ci" }
      expect(framework_ci_report.fetch(:final_content)).to include("name: Rails CI")
      expect(framework_ci_report.fetch(:final_content)).to include("gemfiles/rails_7_0")
      expect(framework_ci_report.fetch(:final_content)).to include("BUNDLE_GEMFILE")
      custom_ci_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == ".github/workflows/custom-ci.yml"
      end
      expect(custom_ci_report.fetch(:final_content)).to include("permissions:")
      expect(custom_ci_report.fetch(:final_content)).to include("concurrency:")
      expect(custom_ci_report.fetch(:final_content)).to include("actions/checkout@de0fac2")
      expect(custom_ci_report.fetch(:final_content)).to include("ruby/setup-ruby@e65c17")
      expect(custom_ci_report.fetch(:final_content)).to include("Upload coverage to Coveralls")
      expect(custom_ci_report.fetch(:final_content)).to include("qltysh/qlty-action/coverage@a192421")
      expect(custom_ci_report.fetch(:final_content)).to include("Code Coverage Summary Report")
      expect(custom_ci_report.fetch(:final_content)).to include("ruby: [\"3.2\", \"3.3\"]")
      obsolete_workflow_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == ".github/workflows/ancient.yml"
      end
      expect(obsolete_workflow_report.fetch(:metadata).fetch(:delete_file)).to be(true)
      expect(obsolete_workflow_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :deleted_file)).to eq(
        ".github/workflows/ancient.yml"
      )

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to eq(fixture.fetch(:expected).fetch(:changed_files))
      expect(project_files(root, fixture.fetch(:expected).fetch(:files).keys.map(&:to_s))).to eq(fixture.fetch(:expected).fetch(:files))
    end
  end

  it "generates a coverage workflow when configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-coverage-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            coverage:
              enabled: true
              appraisal: coverage
              command: rake test
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      coverage_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_actions_coverage_ci" }
      expect(coverage_report.dig(:request_envelope, :request, :provider_family)).to eq("yaml")
      expect(coverage_report.fetch(:relative_path)).to eq(".github/workflows/coverage.yml")
      expect(coverage_report.fetch(:final_content)).to include("name: Test Coverage")
      expect(coverage_report.fetch(:final_content)).to include("K_SOUP_COV_DO: true")
      expect(coverage_report.fetch(:final_content)).to include("bundle exec appraisal ${{ matrix.appraisal }} bundle exec ${{ matrix.exec_cmd }}")
      expect(coverage_report.fetch(:final_content)).to include("Upload coverage to CodeCov")
      expect(plan[:changed_files]).to include(".github/workflows/coverage.yml")
    end
  end

  it "removes Open Collective funding when disabled" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
          templates:
            root: template
            entries:
              - README.md
              - source: FUNDING.md.example
                target: FUNDING.md
        YAML
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: example
        YAML
        ".github/workflows/opencollective.yml" => <<~YAML,
          name: Open Collective
          on:
            workflow_dispatch:
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: actions/checkout@v3
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # Example

          Open Collective enabled.
        MARKDOWN
        "template/README.md.no-osc.example" => <<~MARKDOWN,
          # Example

          Open Collective disabled.
        MARKDOWN
        "template/FUNDING.md.example" => <<~MARKDOWN,
          # Funding
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_disabled_source)).to eq("config.funding.open_collective")
      expect(plan.dig(:facts, :funding, :open_collective_files)).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe.fetch(:name) }
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_opencollective_yml")
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_github_workflows_opencollective_yml")
      expect(recipe_names).not_to include("github_actions_workflow_snippets_github_workflows_opencollective_yml")
      expect(plan.dig(:facts, :templates, :source_preferences)).to eq(
        [
          {
            target_path: "README.md",
            configured_source: "README.md",
            selected_source: "template/README.md.no-osc.example",
            selection_reason: "opencollective_disabled_no_osc_variant",
            apply: false,
          },
          {
            target_path: "FUNDING.md",
            configured_source: "FUNDING.md.example",
            selected_source: "template/FUNDING.md.example",
            selection_reason: "default_example_variant",
            apply: false,
          },
        ]
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.fetch(:changed)).to be(false)
      expect(template_report.dig(:metadata, :template_source_preference, :selected_source)).to eq(
        "template/README.md.no-osc.example"
      )
      expect(template_report.dig(:request_envelope, :request, :runtime_context, :template_source_preference, :selection_reason)).to eq(
        "opencollective_disabled_no_osc_variant"
      )
      funding_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_funding_yml" }
      expect(funding_report.fetch(:final_content)).not_to include("open_collective")
      expect(funding_report.fetch(:final_content)).to include("tidelift: rubygems/example")
      open_collective_reports = plan[:recipe_reports].select do |report|
        report.fetch(:recipe_name).start_with?("opencollective_disabled_file_cleanup_")
      end
      expect(open_collective_reports.map { |report| report.fetch(:relative_path) }).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(open_collective_reports).to all(satisfy { |report| report.fetch(:metadata).fetch(:delete_file) == true })

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to include(".opencollective.yml", ".github/workflows/opencollective.yml")
      expect(File).not_to exist(File.join(root, ".opencollective.yml"))
      expect(File).not_to exist(File.join(root, ".github/workflows/opencollective.yml"))
    end
  end

  it "honors falsey Open Collective environment variables when config is absent" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-env-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: { "OPENCOLLECTIVE_HANDLE" => "NO" })
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_disabled_source)).to eq("env.OPENCOLLECTIVE_HANDLE")
      expect(plan.dig(:facts, :funding, :open_collective_org)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      expect(plan[:changed_files]).to include(".opencollective.yml")
    end
  end

  it "lets explicit Open Collective config override falsey environment variables" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-config-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: true
        YAML
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: { "FUNDING_ORG" => "0" })
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/example")
    end
  end

  it "discovers Open Collective org from environment before .opencollective.yml" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-env-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            entries:
              - README.md
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: yaml-org
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: { "FUNDING_ORG" => "env-org" })
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("env-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("env.FUNDING_ORG")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/env-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include(
        "KJ|GEM_NAME" => "example",
        "KJ|GEM_NAME_PATH" => "example",
        "KJ|NAMESPACE" => "Example",
        "KJ|OPENCOLLECTIVE_ORG" => "env-org"
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.dig(:metadata, :template_tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "env-org")
      expect(template_report.dig(:request_envelope, :request, :runtime_context, :template_tokens)).to include(
        "KJ|OPENCOLLECTIVE_ORG" => "env-org"
      )
    end
  end

  it "discovers Open Collective org from .opencollective.yml when env is absent" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-yaml-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".opencollective.yml" => <<~YAML,
          org: yaml-org
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("yaml-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq(".opencollective.yml")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/yaml-org")
    end
  end

  it "applies selected template content with projected tokens when configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-application-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => "# old\n",
        ".opencollective.yml" => <<~YAML,
          collective: yaml-org
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|GEM_NAME}

          Namespace: {KJ|NAMESPACE}
          Path: {KJ|GEM_NAME_PATH}
          Ruby: {KJ|MIN_RUBY}
          Author: {KJ|AUTHOR:NAME}
          Given: {KJ|AUTHOR:GIVEN_NAMES}
          Family: {KJ|AUTHOR:FAMILY_NAMES}
          Email: {KJ|AUTHOR:EMAIL}
          Domain: {KJ|AUTHOR:DOMAIN}
          Funding: {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:changed)).to be(true)
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include("{KJ|GEM_NAME}")
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        # example

        Namespace: Example
        Path: example
        Ruby: 3.2
        Author: Jane Q Public
        Given: Jane Q
        Family: Public
        Email: jane@example.test
        Domain: example.test
        Funding: yaml-org
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|AUTHOR:DOMAIN" => "example.test",
        "KJ|AUTHOR:EMAIL" => "jane@example.test",
        "KJ|AUTHOR:FAMILY_NAMES" => "Public",
        "KJ|AUTHOR:GIVEN_NAMES" => "Jane Q",
        "KJ|AUTHOR:NAME" => "Jane Q Public",
        "KJ|GEM_NAME" => "example",
        "KJ|GEM_NAME_PATH" => "example",
        "KJ|MIN_RUBY" => "3.2",
        "KJ|NAMESPACE" => "Example",
        "KJ|OPENCOLLECTIVE_ORG" => "yaml-org"
      )

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
    end
  end

  it "applies packaged template files when no project template root exists" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          tokens:
            forge:
              gh_user: acme
              gl_user: acme
              cb_user: acme
              sh_user: acme
            funding:
              patreon: acme
              kofi: acme
              paypal: acme
              buymeacoffee: acme
              polar: acme
              liberapay: acme
              issuehunt: acme
            social:
              mastodon: "@acme@example.social"
              bluesky: acme.example
              linktree: acme
              devto: acme
          templates:
            apply: true
            entries:
              - README.md
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: "README.md.example",
        source_relative_path: "README.md.example",
        source_root: "packaged"
      )
      expect(template_report.dig(:metadata, :template_source_preference, :source_root_path)).to end_with(
        "lib/kettle/jem/templates"
      )
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include("# {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}")
      expect(template_report.fetch(:final_content)).to include("# 💎 Example")
      expect(template_report.fetch(:final_content)).to include("Compatible with MRI Ruby 3.2+")
      expect(template_report.fetch(:final_content)).to include("https://patreon.com/acme")
      expect(template_report.fetch(:final_content)).to include("https://github.com/acme/example")

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
    end
  end

  it "bootstraps kettle config from packaged reference template when missing" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: { "KJ_MIN_DIVERGENCE_THRESHOLD" => "7" })
      bootstrap_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      expect(bootstrap_report.fetch(:changed)).to be(true)
      expect(bootstrap_report.fetch(:relative_path)).to eq(".kettle-jem.yml")
      expect(bootstrap_report.dig(:metadata, :bootstrap_file)).to be(true)
      expect(bootstrap_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: ".kettle-jem.yml.example",
        source_relative_path: ".kettle-jem.yml.example",
        source_root: "packaged"
      )
      expect(bootstrap_report.fetch(:final_content)).to include("# kettle-jem configuration file")
      expect(bootstrap_report.fetch(:final_content)).to include("min_divergence_threshold: 7")
      expect(bootstrap_report.fetch(:final_content)).to include("#   tokens    - values for {KJ|...} placeholders used across template files")

      described_class.apply_project(root, env: { "KJ_MIN_DIVERGENCE_THRESHOLD" => "7" })
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(bootstrap_report.fetch(:final_content))
    end
  end

  it "classifies template entries with files and patterns strategy config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-strategy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          patterns:
            - path: "certs/**"
              strategy: raw_copy
          files:
            README.md:
              strategy: keep_destination
          templates:
            root: template
            apply: true
            entries:
              - README.md
              - source: certs/pboling.pem.example
                target: certs/pboling.pem
        YAML
        "README.md" => "# destination\n",
        "template/README.md.example" => "# {KJ|GEM_NAME}\n",
        "template/certs/pboling.pem.example" => "raw {KJ|GEM_NAME}\n",
      })

      plan = described_class.plan_project(root, env: {})
      readme_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      cert_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_certs_pboling_pem"
      end
      expect(readme_report.fetch(:changed)).to be(false)
      expect(readme_report.fetch(:final_content)).to eq("# destination\n")
      expect(readme_report.dig(:metadata, :template_source_preference)).to include(strategy: "keep_destination")
      expect(cert_report.fetch(:changed)).to be(true)
      expect(cert_report.fetch(:final_content)).to eq("raw {KJ|GEM_NAME}\n")
      expect(cert_report.dig(:metadata, :template_source_preference)).to include(strategy: "raw_copy")
    end
  end

  it "plans packaged template inventory when entries are omitted" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-inventory-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
          patterns:
            - path: "certs/**"
              strategy: raw_copy
          files:
            AGENTS.md:
              strategy: accept_template
          templates:
            root: packaged
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      preferences = plan.dig(:facts, :templates, :source_preferences)
      expect(preferences.size).to be > 100

      agents = preferences.find { |preference| preference.fetch(:target_path) == "AGENTS.md" }
      cert = preferences.find { |preference| preference.fetch(:target_path) == "certs/pboling.pem" }
      envrc = preferences.find { |preference| preference.fetch(:target_path) == ".envrc" }
      env_local = preferences.find { |preference| preference.fetch(:target_path) == ".env.local.example" }
      gemspec = preferences.find { |preference| preference.fetch(:target_path) == "example.gemspec" }

      expect(agents).to include(selected_source: "AGENTS.md.example", strategy: "accept_template")
      expect(cert).to include(selected_source: "certs/pboling.pem.example", strategy: "raw_copy")
      expect(envrc).to include(selected_source: ".envrc.no-osc.example")
      expect(env_local).to include(configured_source: ".env.local", selected_source: ".env.local.example")
      expect(gemspec).to include(configured_source: "gem.gemspec", selected_source: "gem.gemspec.example")
    end
  end

  it "preserves configured README sections during merge template application" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            preserve_sections:
              - synopsis
              - basic usage
              - custom section
            preserve_patterns:
              - "note:*"
            section_aliases:
              usage: basic usage
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          # 1️⃣ Example

          ## Synopsis

          Destination synopsis.

          ## Usage

          Destination usage.

          ## Custom Section

          Destination custom.

          ## Note: Local

          Destination note.

          ## Installation

          Old install.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Template synopsis.

          ## 🔧 Basic Usage

          Template usage.

          ## Custom Section

          Template custom.

          ## Note: Local

          Template note.

          ## Installation

          Template install.
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      readme_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = readme_report.fetch(:final_content)
      expect(final_content).to include("# 💎 Example")
      expect(final_content).to include("## 🌻 Synopsis\n\nDestination synopsis.")
      expect(final_content).to include("## 🔧 Basic Usage\n\nDestination usage.")
      expect(final_content).to include("## Custom Section\n\nDestination custom.")
      expect(final_content).to include("## Note: Local\n\nDestination note.")
      expect(final_content).to include("## Installation\n\nTemplate install.")
      expect(final_content).not_to include("Template synopsis.")
      expect(final_content).not_to include("Template usage.")
      expect(final_content).not_to include("Template custom.")
      expect(final_content).not_to include("Template note.")
      expect(File.read(File.join(root, "README.md"))).to eq(final_content)
    end
  end

  it "merges YAML and TOML template applications with destination values" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            config:
              explicit.yml:
                strategy: merge
                file_type: yaml
          templates:
            root: template
            apply: true
            entries:
              - .github/dependabot.yml
              - config/settings.yml
              - config/tool.toml
              - config/explicit.yml
        YAML
        ".github/dependabot.yml" => <<~YAML,
          updates:
            - package-ecosystem: bundler
              directory: /
          version: 1
        YAML
        "config/settings.yml" => <<~YAML,
          engines:
            - ruby
          nested:
            value: destination
          version: 1
        YAML
        "config/tool.toml" => <<~TOML,
          title = "destination"

          [settings]
          retries = 1
        TOML
        "config/explicit.yml" => <<~YAML,
          destination_only: keep
          nested:
            value: destination
        YAML
        "template/.github/dependabot.yml.example" => <<~YAML,
          schedule:
            interval: weekly
          updates:
            - package-ecosystem: github-actions
              directory: /
          version: 2
        YAML
        "template/config/settings.yml.example" => <<~YAML,
          engines:
            - ruby
            - jruby
          nested:
            template_only: true
            value: template
          version: 2
        YAML
        "template/config/tool.toml.example" => <<~TOML,
          title = "template"

          [settings]
          retries = 3
          timeout = 30
        TOML
        "template/config/explicit.yml.example" => <<~YAML,
          nested:
            value: template
            template_only: true
          template_only: added
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      dependabot_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_github_dependabot_yml"
      end
      yaml_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      toml_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_tool_toml"
      end
      explicit_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_explicit_yml"
      end

      expect(YAML.safe_load(dependabot_report.fetch(:final_content))).to eq(
        "schedule" => { "interval" => "weekly" },
        "updates" => [
          {
            "directory" => "/",
            "package-ecosystem" => "bundler",
          },
        ],
        "version" => 1
      )
      expect(YAML.safe_load(yaml_report.fetch(:final_content))).to eq(
        "engines" => ["ruby"],
        "nested" => {
          "template_only" => true,
          "value" => "destination",
        },
        "version" => 1
      )
      expect(toml_report.fetch(:final_content)).to eq(<<~TOML)
        title = "destination"

        [settings]
        retries = 1
        timeout = 30
      TOML
      expect(YAML.safe_load(explicit_report.fetch(:final_content))).to eq(
        "destination_only" => "keep",
        "nested" => {
          "template_only" => true,
          "value" => "destination",
        },
        "template_only" => "added"
      )
      expect(explicit_report.dig(:metadata, :template_source_preference)).to include(file_type: "yaml")
    end
  end

  it "honors author template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-author-token-override-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            author:
              name: Config Person
              given_names: Config
              family_names: Person
              email: config@example.test
              domain: config.example.test
              orcid: "{KJ|AUTHOR:ORCID}"
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Author: {KJ|AUTHOR:NAME}
          Given: {KJ|AUTHOR:GIVEN_NAMES}
          Family: {KJ|AUTHOR:FAMILY_NAMES}
          Email: {KJ|AUTHOR:EMAIL}
          Domain: {KJ|AUTHOR:DOMAIN}
          ORCID: {KJ|AUTHOR:ORCID}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_AUTHOR_NAME" => "Env A Writer",
          "KJ_AUTHOR_EMAIL" => "env@example.test",
          "KJ_AUTHOR_DOMAIN" => "env.example.test",
          "KJ_AUTHOR_ORCID" => "0000-0002-1825-0097",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Author: Env A Writer
        Given: Config
        Family: Person
        Email: env@example.test
        Domain: env.example.test
        ORCID: 0000-0002-1825-0097
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|AUTHOR:DOMAIN" => "env.example.test",
        "KJ|AUTHOR:EMAIL" => "env@example.test",
        "KJ|AUTHOR:FAMILY_NAMES" => "Person",
        "KJ|AUTHOR:GIVEN_NAMES" => "Config",
        "KJ|AUTHOR:NAME" => "Env A Writer",
        "KJ|AUTHOR:ORCID" => "0000-0002-1825-0097"
      )
    end
  end

  it "honors forge user template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-forge-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            forge:
              gh_user: config-gh
              gl_user: config-gl
              cb_user: "{KJ|CB:USER}"
              sh_user: config-sh
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          GitHub: {KJ|GH:USER}
          GitLab: {KJ|GL:USER}
          Codeberg: {KJ|CB:USER}
          SourceHut: {KJ|SH:USER}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_GH_USER" => "env-gh",
          "KJ_CB_USER" => "env-cb",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        GitHub: env-gh
        GitLab: config-gl
        Codeberg: env-cb
        SourceHut: config-sh
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|CB:USER" => "env-cb",
        "KJ|GH:USER" => "env-gh",
        "KJ|GL:USER" => "config-gl",
        "KJ|SH:USER" => "config-sh"
      )
    end
  end

  it "honors funding platform template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-funding-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            funding:
              patreon: config-patreon
              kofi: config-kofi
              paypal: "{KJ|FUNDING:PAYPAL}"
              buymeacoffee: config-bmac
              polar: config-polar
              liberapay: config-liberapay
              issuehunt: config-issuehunt
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Patreon: {KJ|FUNDING:PATREON}
          Ko-fi: {KJ|FUNDING:KOFI}
          PayPal: {KJ|FUNDING:PAYPAL}
          BuyMeACoffee: {KJ|FUNDING:BUYMEACOFFEE}
          Polar: {KJ|FUNDING:POLAR}
          Liberapay: {KJ|FUNDING:LIBERAPAY}
          IssueHunt: {KJ|FUNDING:ISSUEHUNT}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_FUNDING_PATREON" => "env-patreon",
          "KJ_FUNDING_PAYPAL" => "env-paypal",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Patreon: env-patreon
        Ko-fi: config-kofi
        PayPal: env-paypal
        BuyMeACoffee: config-bmac
        Polar: config-polar
        Liberapay: config-liberapay
        IssueHunt: config-issuehunt
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|FUNDING:BUYMEACOFFEE" => "config-bmac",
        "KJ|FUNDING:ISSUEHUNT" => "config-issuehunt",
        "KJ|FUNDING:KOFI" => "config-kofi",
        "KJ|FUNDING:LIBERAPAY" => "config-liberapay",
        "KJ|FUNDING:PATREON" => "env-patreon",
        "KJ|FUNDING:PAYPAL" => "env-paypal",
        "KJ|FUNDING:POLAR" => "config-polar"
      )
    end
  end

  it "honors social template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-social-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            social:
              mastodon: config-mastodon
              bluesky: config-bluesky
              linktree: "{KJ|SOCIAL:LINKTREE}"
              devto: config-devto
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Mastodon: {KJ|SOCIAL:MASTODON}
          Bluesky: {KJ|SOCIAL:BLUESKY}
          Linktree: {KJ|SOCIAL:LINKTREE}
          Dev.to: {KJ|SOCIAL:DEVTO}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_SOCIAL_MASTODON" => "env-mastodon",
          "KJ_SOCIAL_LINKTREE" => "env-linktree",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Mastodon: env-mastodon
        Bluesky: config-bluesky
        Linktree: env-linktree
        Dev.to: config-devto
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|SOCIAL:BLUESKY" => "config-bluesky",
        "KJ|SOCIAL:DEVTO" => "config-devto",
        "KJ|SOCIAL:LINKTREE" => "env-linktree",
        "KJ|SOCIAL:MASTODON" => "env-mastodon"
      )
    end
  end

  it "projects license template tokens from configured licenses" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-license-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.licenses = ["MIT"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          licenses:
            - AGPL-3.0-only
            - PolyForm-Small-Business-1.0.0
            - LicenseRef-Big-Time-Public-License
          templates:
            root: template
            apply: true
            entries:
              - LICENSE.md
        YAML
        "template/LICENSE.md.example" => <<~MARKDOWN,
          Primary: {KJ|LICENSE:PRIMARY_SPDX}
          Prefix: {KJ|COPYRIGHT_PREFIX}
          Badge: {KJ|README:LICENSE_BADGE}
          Compat: {KJ|README:LICENSE_COMPAT_BADGE}
          Refs:
          {KJ|README:LICENSE_REFS}
          Intro:
          {KJ|README:LICENSE_INTRO}
          Content:
          {KJ|LICENSE_MD_CONTENT}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_LICENSE_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(plan.dig(:facts, :license, :spdx)).to eq(
        ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0", "LicenseRef-Big-Time-Public-License"]
      )
      expect(plan.dig(:facts, :package, :license_expression)).to eq(
        "AGPL-3.0-only OR PolyForm-Small-Business-1.0.0 OR LicenseRef-Big-Time-Public-License"
      )
      expect(final_content).to include("Primary: AGPL-3.0-only")
      expect(final_content).to include("Prefix: Required Notice: ")
      expect(final_content).to include("[AGPL-3.0-only](AGPL-3.0-only.md)")
      expect(final_content).to include("[PolyForm-Small-Business-1.0.0](PolyForm-Small-Business-1.0.0.md)")
      expect(final_content).to include("[Big-Time-Public-License](Big-Time-Public-License.md)")
      expect(final_content).to include("Apache license compatibility: Category X")
      expect(final_content).to include("## Use-case guide")
      expect(final_content).to include("[contact us](mailto:jane@example.test)")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|COPYRIGHT_PREFIX" => "Required Notice: ",
        "KJ|LICENSE:PRIMARY_SPDX" => "AGPL-3.0-only"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|LICENSE_MD_CONTENT")).to include(
        "This project is made available under the following licenses."
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:LICENSE_REFS")).to include(
        "AGPL-3.0-only.md"
      )
    end
  end

  it "projects project runtime template tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-project-runtime-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "2.4.6"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          min_divergence_threshold: "{KJ|MIN_DIVERGENCE_THRESHOLD}"
          defaults:
            freeze_token: custom-freeze
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Gem shield: {KJ|GEM_SHIELD}
          Major: {KJ|GEM_MAJOR}
          GitHub org: {KJ|GH_ORG}
          Namespace shield: {KJ|NAMESPACE_SHIELD}
          Min dev Ruby: {KJ|MIN_DEV_RUBY}
          Freeze: {KJ|FREEZE_TOKEN}
          Version: {KJ|KETTLE_JEM_VERSION}
          Date: {KJ|TEMPLATE_RUN_DATE}
          Year: {KJ|TEMPLATE_RUN_YEAR}
          Dev gem: {KJ|KETTLE_DEV_GEM}
          YARD: {KJ|YARD_HOST}
          Emoji: {KJ|PROJECT_EMOJI}
          Divergence: {KJ|MIN_DIVERGENCE_THRESHOLD}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: { "KJ_MIN_DIVERGENCE_THRESHOLD" => "12" })
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Gem shield: example--gem")
      expect(final_content).to include("Major: 2")
      expect(final_content).to include("GitHub org: acme")
      expect(final_content).to include("Namespace shield: Example%3A%3AGem")
      expect(final_content).to include("Min dev Ruby: 3.2")
      expect(final_content).to include("Freeze: custom-freeze")
      expect(final_content).to include("Version: #{Kettle::Jem::VERSION}")
      expect(final_content).to include("Date: #{Time.now.strftime("%Y-%m-%d")}")
      expect(final_content).to include("Year: #{Time.now.year}")
      expect(final_content).to include("Dev gem: kettle-dev")
      expect(final_content).to include("YARD: example-gem.example.test")
      expect(final_content).to include("Emoji: 🫖")
      expect(final_content).to include("Divergence: 12")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|FREEZE_TOKEN" => "custom-freeze",
        "KJ|GEM_MAJOR" => "2",
        "KJ|GEM_SHIELD" => "example--gem",
        "KJ|GH_ORG" => "acme",
        "KJ|MIN_DEV_RUBY" => "3.2",
        "KJ|MIN_DIVERGENCE_THRESHOLD" => "12",
        "KJ|NAMESPACE_SHIELD" => "Example%3A%3AGem",
        "KJ|PROJECT_EMOJI" => "🫖",
        "KJ|YARD_HOST" => "example-gem.example.test"
      )
    end
  end

  it "projects README top logo template tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-logo-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Galtzo FLOSS Logo")
      expect(final_content).to include("ruby-lang Logo")
      expect(final_content).to include("[![acme Logo by Aboling0, CC BY-SA 4.0][🖼️acme-i]][🖼️acme]")
      expect(final_content).to include("[![example-gem Logo by Aboling0, CC BY-SA 4.0][🖼️example-gem-i]][🖼️example-gem]")
      expect(final_content).to include("[🖼️acme-i]: https://logos.galtzo.com/assets/images/acme/avatar-192px.svg")
      expect(final_content).to include("[🖼️example-gem]: https://github.com/acme/example-gem")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|README:TOP_LOGO_REFS" => a_string_including("https://github.com/acme/example-gem"),
        "KJ|README:TOP_LOGO_ROW" => a_string_including("example-gem Logo by Aboling0")
      )
    end
  end

  it "projects RuboCop LTS template tokens from minimum Ruby" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubocop-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.1"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/style.gemfile
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_gemfiles_modular_style_gemfile"
      end
      expect(template_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: "gemfiles/modular/style.gemfile.example",
        source_relative_path: "gemfiles/modular/style.gemfile.example",
        source_root: "packaged"
      )
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include(
        "We run rubocop on the latest version of Ruby"
      )
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-lts", "~> 22.0"')
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-ruby3_1"')
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|RUBOCOP_LTS_CONSTRAINT" => "~> 22.0",
        "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby3_1"
      )
    end
  end

  it "fails fast when template application leaves unresolved tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-unresolved-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|UNKNOWN}
        MARKDOWN
      })

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /unresolved kettle-jem template tokens: \{KJ\|UNKNOWN\}/)
    end
  end
end
