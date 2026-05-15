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

  it "applies README style conditionals and reports missing integrations" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["PolyForm-Noncommercial-1.0.0"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - README.md
          readme:
            integrations:
              coveralls: false
        YAML
        "templates/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          [![CodeCov Test Coverage][🏀codecovi]][🏀codecov] [![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls] [![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov] [![QLTY Maintainability][🏀qlty-mnti]][🏀qlty-mnt] [![CodeQL][🖐codeQL-img]][🖐codeQL]

          ## 🌻 Synopsis

          Template synopsis.

          ## 🦷 FLOSS Funding

          Funding template text.

          ## 🔐 Security

          Security template text.

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.
        MARKDOWN
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Project synopsis.

          ## ⚙️ Configuration

          Project configuration.

          ## 🔧 Basic Usage

          Project usage.
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "template_source_application_README_md" }
      expect(report.fetch(:final_content)).to include("Project synopsis.")
      expect(report.fetch(:final_content)).to include("Project configuration.")
      expect(report.fetch(:final_content)).to include("Project usage.")
      expect(report.fetch(:final_content)).not_to include("## 🦷 FLOSS Funding")
      expect(report.fetch(:final_content)).not_to include("## 🔐 Security")
      expect(report.fetch(:final_content)).not_to include("CodeCov Test Coverage")
      expect(report.fetch(:final_content)).not_to include("Coveralls Test Coverage")
      expect(report.fetch(:final_content)).not_to include("QLTY Test Coverage")
      expect(report.fetch(:final_content)).not_to include("CodeQL")
      expect(report.dig(:metadata, :readme_style, :floss_funding_enabled)).to be(false)
      expect(report.dig(:metadata, :readme_style, :security_enabled)).to be(false)
      expect(report.dig(:metadata, :readme_style, :disabled_integrations)).to eq(["coveralls"])
      expect(report.dig(:metadata, :readme_style, :missing_integrations)).to contain_exactly("codecov", "qlty", "codeql")
    end
  end

  it "creates a package README through the packaged README style API" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-api-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:changed)).to be(true)
      expect(plan.fetch(:final_content)).to include("# 💎 Example")
      expect(plan.fetch(:final_content)).to include("## 🌻 Synopsis")
      expect(plan.fetch(:final_content)).to include("StructuredMerge packages provide fixture-backed merge behavior")
      expect(plan.fetch(:final_content)).not_to include("Tokens to Remember")

      apply = described_class.apply_readme_style(root, env: {})
      expect(apply.fetch(:changed)).to be(true)
      expect(File.read(File.join(root, "README.md"))).to eq(apply.fetch(:final_content))
      expect(described_class.plan_readme_style(root, env: {}).fetch(:changed)).to be(false)
    end
  end

  it "fills configured README section partials while preserving unconfigured manual sections" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-partials-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
          readme:
            section_partials:
              synopsis: readme/partials/synopsis.md
              configuration: readme/partials/configuration.md
              basic_usage: readme/partials/basic_usage.md
        YAML
        "templates/readme/partials/synopsis.md.example" => "Generated synopsis for {KJ|GEM_NAME}.\\n",
        "templates/readme/partials/configuration.md.example" => "Generated configuration.\\n",
        "templates/readme/partials/basic_usage.md.example" => "Generated usage.\\n",
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Old synopsis.

          ## ⚙️ Configuration

          Old configuration.

          ## 🔧 Basic Usage

          Old usage.
        MARKDOWN
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:final_content)).to include("Generated synopsis for example.")
      expect(plan.fetch(:final_content)).to include("Generated configuration.")
      expect(plan.fetch(:final_content)).to include("Generated usage.")
      expect(plan.fetch(:final_content)).not_to include("Old synopsis.")
      expect(plan.fetch(:final_content)).not_to include("Old configuration.")
      expect(plan.fetch(:final_content)).not_to include("Old usage.")
      expect(plan.dig(:readme_style, :section_partials, "synopsis", :selected_source)).to eq(
        "templates/readme/partials/synopsis.md.example"
      )
    end
  end

  it "loads packaged README section partials" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-readme-partials-slice", tmp_root) do |root|
      write_tree(root, {
        "kettle-jem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-jem"
            spec.summary = "Kettle Jem"
            spec.homepage = "https://github.com/structuredmerge/kettle-jem"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
          readme:
            section_partials:
              synopsis: readme/partials/synopsis.md
              configuration: readme/partials/configuration.md
              basic_usage: readme/partials/basic_usage.md
        YAML
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:final_content)).to include("Kettle template tool")
      expect(plan.fetch(:final_content)).to include("Configuration shape")
      expect(plan.fetch(:final_content)).to include("bundle exec rake kettle:jem:install")
      expect(plan.dig(:readme_style, :section_partials, "configuration", :source_root)).to eq("packaged")
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
            root: packaged
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
      expect(plan.dig(:facts, :templates, :source_preferences)).to contain_exactly(
        a_hash_including(
          target_path: "README.md",
          configured_source: "README.md",
          selected_source: "README.md.no-osc.example",
          source_relative_path: "README.md.no-osc.example",
          source_root: "packaged",
          selection_reason: "opencollective_disabled_no_osc_variant",
          apply: false
        ),
        a_hash_including(
          target_path: "FUNDING.md",
          configured_source: "FUNDING.md.example",
          selected_source: "FUNDING.md.no-osc.example",
          source_relative_path: "FUNDING.md.no-osc.example",
          source_root: "packaged",
          selection_reason: "opencollective_disabled_no_osc_variant",
          apply: false
        )
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.fetch(:changed)).to be(false)
      expect(template_report.dig(:metadata, :template_source_preference, :selected_source)).to eq(
        "README.md.no-osc.example"
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
            root: packaged
            apply: true
            entries:
              - README.md
              - source: certs/pboling.pem.example
                target: certs/pboling.pem
        YAML
        "README.md" => "# destination\n",
      })

      packaged_cert = File.read(File.join(__dir__, "../lib/kettle/jem/templates/certs/pboling.pem.example"))
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
      expect(cert_report.fetch(:final_content)).to eq(packaged_cert)
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

  it "applies remaining-files copy-only and legacy destination policies" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-remaining-files-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
              - .github/copilot_instructions.md
        YAML
        "bin/setup" => "custom setup\n",
        ".github/COPILOT_INSTRUCTIONS.md" => "legacy copilot instructions\n",
      })

      plan = described_class.plan_project(root, env: {})
      setup_preference = plan.dig(:facts, :templates, :source_preferences).find do |preference|
        preference.fetch(:target_path) == "bin/setup"
      end
      setup_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_bin_setup"
      end
      legacy_cleanup = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_legacy_destination_cleanup_github_COPILOT_INSTRUCTIONS_md"
      end

      expect(setup_preference).to include(
        strategy: "keep_destination",
        policy: "copy_only_when_missing"
      )
      expect(setup_report.fetch(:changed)).to be(false)
      expect(setup_report.fetch(:final_content)).to eq("custom setup\n")
      expect(legacy_cleanup.dig(:metadata, :delete_file)).to be(true)
      expect(legacy_cleanup.dig(:report_envelope, :report, :step_reports, 0, :metadata)).to include(
        policy_kind: "delete_legacy_destination_file",
        deleted_file: ".github/COPILOT_INSTRUCTIONS.md"
      )

      apply = described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "bin/setup"))).to eq("custom setup\n")
      expect(File.exist?(File.join(root, ".github/copilot_instructions.md"))).to be(true)
      expect(File.exist?(File.join(root, ".github/COPILOT_INSTRUCTIONS.md"))).to be(false)
      expect(apply.fetch(:changed_files)).to include(".github/COPILOT_INSTRUCTIONS.md")
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

  it "merges Ruby-family template applications with destination declarations and DSL calls" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ruby-merge-slice", tmp_root) do |root|
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
              - Gemfile
              - Rakefile
              - lib/example.rb
        YAML
        "Gemfile" => <<~RUBY,
          source "https://rubygems.org"
          gem "rspec"
          gem "example", path: "../example"
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
        "Rakefile" => <<~RUBY,
          desc "Default"
          task :default do
            puts "destination"
          end
        RUBY
        "lib/example.rb" => <<~RUBY,
          require "set"

          class Existing
            def keep
              :destination
            end
          end
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          source "https://gem.coop"
          gemspec
          eval_gemfile "gemfiles/modular/style.gemfile"
          gem "appraisal"
          gem "example", path: "."
          gem "rake"
        RUBY
        "template/Rakefile.example" => <<~RUBY,
          desc "Default"
          task :default do
            puts "template"
          end

          desc "CI"
          task :ci do
            sh "bundle exec rspec"
          end
        RUBY
        "template/lib/example.rb.example" => <<~RUBY,
          require "json"

          class Existing
            def keep
              :template
            end
          end

          class Added
            def call
              :template_only
            end
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      ruby_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_lib_example_rb"
      end
      gemfile_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Gemfile"
      end
      rakefile_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Rakefile"
      end
      final_content = ruby_report.fetch(:final_content)

      expect(final_content).to include('require "set"')
      expect(final_content).not_to include('require "json"')
      expect(final_content).to include("def keep\n    :destination\n  end")
      expect(final_content).to include("class Added")
      expect(final_content).to include(":template_only")
      expect(File.read(File.join(root, "lib/example.rb"))).to eq(final_content)

      gemfile_content = gemfile_report.fetch(:final_content)
      expect(gemfile_content).to include('source "https://gem.coop"')
      expect(gemfile_content).to include("gemspec")
      expect(gemfile_content.scan('eval_gemfile "gemfiles/modular/style.gemfile"').size).to eq(1)
      expect(gemfile_content).to include('gem "rspec"')
      expect(gemfile_content).to include('gem "rake"')
      expect(gemfile_content).not_to include('gem "appraisal"')
      expect(gemfile_content).not_to include('gem "example"')
      expect(gemfile_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "gemfile",
        operations: include(
          include(operation: "delete_dependency_declarations", deleted_gems: contain_exactly("appraisal", "example"))
        )
      )

      rakefile_content = rakefile_report.fetch(:final_content)
      expect(rakefile_content.scan(/task\s+:default/).size).to eq(1)
      expect(rakefile_content).to include('puts "destination"')
      expect(rakefile_content).to include("task :ci")
    end
  end

  it "applies Appraisals template policy with self-dependency and minimum Ruby pruning" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisals-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "Appraisals" => <<~RUBY,
          # frozen_string_literal: true

          appraise "ruby-2-7" do
            gem "example"
            eval_gemfile "gemfiles/modular/x_std_libs/r2/libs.gemfile"
          end

          appraise "ruby-3-2" do
            gem "example", path: "../example"
            eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "coverage" do
            gem "simplecov"
          end
        RUBY
        "template/Appraisals.example" => <<~RUBY,
          # frozen_string_literal: true

          appraise "ruby-3-2" do
            eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "style" do
            eval_gemfile "gemfiles/modular/style.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      appraisals_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Appraisals"
      end
      appraisals_content = appraisals_report.fetch(:final_content)

      expect(appraisals_content).not_to include('appraise "ruby-2-7"')
      expect(appraisals_content).not_to include('gem "example"')
      expect(appraisals_content).to include('appraise "ruby-3-2"')
      expect(appraisals_content).to include('eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"')
      expect(appraisals_content).to include('appraise "coverage"')
      expect(appraisals_content).to include('gem "simplecov"')
      expect(appraisals_content).to include('appraise "style"')
      expect(appraisals_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "appraisals",
        operations: include(
          include(operation: "merge_appraisal_blocks", inserted_appraisals: include("style")),
          include(operation: "delete_self_dependency_declarations", deleted_dependency_count: 2),
          include(operation: "prune_minimum_ruby_appraisals", deleted_appraisals: include("ruby-2-7"))
        )
      )
      expect(File.read(File.join(root, "Appraisals"))).to eq(appraisals_content)
    end
  end

  it "normalizes preserved gemspec lines to the template block receiver" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-receiver-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 3.2"
            gem.add_runtime_dependency "json", ">= 2.7"
            gem.add_development_dependency "rubocop", "~> 1.70"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 3.1"
            spec.add_runtime_dependency "json", ">= 2.0"
            spec.add_development_dependency "rspec", "~> 3.13"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include('spec.summary = "Real summary"')
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 3.2"')
      expect(gemspec_content).to include('spec.add_runtime_dependency "json", ">= 2.7"')
      expect(gemspec_content).to include('spec.add_development_dependency "rubocop", "~> 1.70"')
      expect(gemspec_content).not_to include("gem.summary")
      expect(gemspec_content).not_to include("gem.add_runtime_dependency")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "gemspec",
        operations: include(
          include(operation: "preserve_project_fields", preserved_fields: include("required_ruby_version", "summary")),
          include(operation: "preserve_dependency_declarations", preserved_dependencies: include("json", "rubocop")),
          include(operation: "normalize_gemspec_receiver", from: "gem", to: "spec")
        )
      )
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
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
            root: packaged
            apply: true
            entries:
              - LICENSE.md
        YAML
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
      expect(final_content).to include("[AGPL-3.0-only](AGPL-3.0-only.md)")
      expect(final_content).to include("[PolyForm-Small-Business-1.0.0](PolyForm-Small-Business-1.0.0.md)")
      expect(final_content).to include("[Big-Time-Public-License](Big-Time-Public-License.md)")
      expect(final_content).to include("## Use-case guide")
      expect(final_content).to include("Required Notice: Copyright")
      expect(final_content).to include("Jane Q Public")
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
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:FAMILY_INTRO_BACKEND_MATRIX")).to include(
        "tree-sitter-language-pack"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:FAMILY_INTRO_BACKEND_MATRIX")).to include(
        "bash-merge, dotenv-merge, rbs-merge"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:FAMILY_INTRO_BACKEND_MATRIX")).to include(
        "Freeze tokens"
      )
    end
  end

  it "projects copyright holders from git blame into license templates" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-copyright-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Fallback Author"]
            spec.email = ["fallback@example.test"]
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "lib/example.rb" => <<~RUBY,
          module Example
            VERSION = "0.1.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - LICENSE.md
              - README.md
        YAML
        "templates/LICENSE.md.example" => <<~MARKDOWN,
          {KJ|LICENSE_MD_CONTENT}

          {KJ|LICENSE_COPYRIGHT_NOTICE}
        MARKDOWN
        "templates/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Template synopsis.

          ## 📄 License

          {KJ|README:LICENSE_INTRO}

          ### © Copyright

          {KJ|README:COPYRIGHT_NOTICE}

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.
        MARKDOWN
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Project synopsis.

          ## ⚙️ Configuration

          Project configuration.

          ## 🔧 Basic Usage

          Project usage.
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "config", "user.name", "Jane Contributor")).to be(true)
      expect(system("git", "-C", root, "config", "user.email", "jane@example.test")).to be(true)
      expect(system("git", "-C", root, "add", ".")).to be(true)
      commit_env = {
        "GIT_AUTHOR_NAME" => "Jane Contributor",
        "GIT_AUTHOR_EMAIL" => "jane@example.test",
        "GIT_AUTHOR_DATE" => "#{Time.now.utc.year}-01-02T00:00:00Z",
        "GIT_COMMITTER_NAME" => "Jane Contributor",
        "GIT_COMMITTER_EMAIL" => "jane@example.test",
        "GIT_COMMITTER_DATE" => "#{Time.now.utc.year}-01-02T00:00:00Z",
      }
      tree = IO.popen(["git", "-C", root, "write-tree"], &:read).strip
      commit = IO.popen(commit_env, ["git", "-C", root, "commit-tree", tree, "-m", "initial"], &:read).strip
      expect(commit).to match(/\A[0-9a-f]{40}\z/)
      expect(system("git", "-C", root, "update-ref", "refs/heads/main", commit)).to be(true)

      plan = described_class.plan_project(root, env: {})
      license_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "template_source_application_LICENSE_md" }
      readme_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "template_source_application_README_md" }
      expected_line = "Copyright (c) #{Time.now.utc.year} Jane Contributor"
      expect(plan.dig(:facts, :copyright, :lines)).to eq([expected_line])
      expect(license_report.fetch(:final_content)).to include("## Copyright Notice")
      expect(license_report.fetch(:final_content)).to include(expected_line)
      expect(readme_report.fetch(:final_content)).to include("Copyright holders")
      expect(readme_report.fetch(:final_content)).to include("- #{expected_line}")
      expect(license_report.dig(:metadata, :template_tokens, "KJ|LICENSE_COPYRIGHT_NOTICE")).to include(expected_line)
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

  it "projects configured README logo row entries by normalized logo type" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-typed-logo-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            logo_row:
              enabled: true
              logos:
                - type: language
                  slug: ruby-lang
                  alt: Ruby language logo
                - type: org
                  slug: acme
                  alt: Acme org logo
                - type: affiliated_project
                  slug: tree-sitter/tree-sitter
                  alt: Tree-sitter project logo
                - type: project
                  slug: acme/ignored
                  alt: Ignored fourth logo
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
      expect(final_content).to include("[![Ruby language Logo by Aboling0, CC BY-SA 4.0][🖼️ruby-lang-i]][🖼️ruby-lang]")
      expect(final_content).to include("[![Acme org Logo by Aboling0, CC BY-SA 4.0][🖼️acme-i]][🖼️acme]")
      expect(final_content).to include("[![Tree-sitter project Logo by Aboling0, CC BY-SA 4.0][🖼️tree-sitter-tree-sitter-i]][🖼️tree-sitter-tree-sitter]")
      expect(final_content).to include("[🖼️tree-sitter-tree-sitter-i]: https://logos.galtzo.com/assets/images/tree-sitter/tree-sitter/avatar-192px.svg")
      expect(final_content).not_to include("Ignored fourth logo")
    end
  end

  it "omits the deprecated secure installation section from packaged README templates" do
    template_root = described_class::PACKAGED_TEMPLATE_ROOT

    expect(File.read(File.join(template_root, "README.md.example"))).not_to include("### 🔒 Secure Installation")
    expect(File.read(File.join(template_root, "README.md.no-osc.example"))).not_to include("### 🔒 Secure Installation")
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

  it "reports template checksum drift" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-drift-slice", tmp_root) do |root|
      write_tree(root, {
        "templates/README.md.example" => "# Example\n",
        "templates/.github/FUNDING.yml.example" => "github: [example]\n",
        ".kettle-jem.yml" => <<~YAML,
          project: example

          kettle-jem:
            version: "0.1.0"
            checksums:
              "README.md.example": "old"
              "removed.md.example": "gone"
        YAML
      })

      current = described_class::TemplateChecksums.compute(template_root: File.join(root, "templates"))
      stored = described_class::TemplateChecksums.load_stored(config_path: File.join(root, ".kettle-jem.yml"))
      drift = described_class::TemplateChecksums.diff(current: current, stored: stored)

      expect(current.keys).to eq([".github/FUNDING.yml.example", "README.md.example"])
      expect(drift).to eq(
        added: [".github/FUNDING.yml.example"],
        changed: ["README.md.example"],
        removed: ["removed.md.example"]
      )
      expect(described_class::TemplateChecksums.diff_count(drift)).to eq(3)
      expect(described_class::TemplateChecksums.summary(drift)).to eq(
        "3 template file(s) since last run: 1 added, 1 changed, 1 removed"
      )
      expect(described_class::TemplateChecksums.detail_lines(drift)).to eq([
        "  + .github/FUNDING.yml.example",
        "  ~ README.md.example",
        "  - removed.md.example",
      ])

      described_class::TemplateChecksums.write_to_config(
        config_path: File.join(root, ".kettle-jem.yml"),
        checksums: current,
        version: "1.2.3"
      )
      rewritten = YAML.safe_load_file(File.join(root, ".kettle-jem.yml"))
      expect(rewritten.fetch("kettle-jem").fetch("version")).to eq("1.2.3")
      expect(rewritten.fetch("kettle-jem").fetch("checksums")).to eq(current)
    end
  end

  it "renders self-test and templating diagnostics reports" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-self-test-report-slice", tmp_root) do |root|
      before = File.join(root, "before")
      after = File.join(root, "after")
      write_tree(before, {
        "same.txt" => "same\n",
        "changed.txt" => "before\n",
        "removed.txt" => "removed\n",
      })
      write_tree(after, {
        "same.txt" => "same\n",
        "changed.txt" => "after\n",
        "added.txt" => "added\n",
      })

      comparison = described_class::SelfTest::Manifest.compare(
        described_class::SelfTest::Manifest.generate(before),
        described_class::SelfTest::Manifest.generate(after)
      ).merge(skipped: ["lib/internal.rb"])
      expect(comparison).to include(
        matched: ["same.txt"],
        changed: ["changed.txt"],
        added: ["added.txt"],
        removed: ["removed.txt"],
        skipped: ["lib/internal.rb"]
      )

      snapshot = {
        workspace_root: root,
        kettle_jem: {
          name: "kettle-jem",
          version: "1.2.3",
          path: File.join(root, "installed", "kettle-jem"),
          local_path: false,
          loaded: true,
        },
        merge_gems: [
          {
            name: "ast-merge",
            version: "2.0.0",
            path: File.join(root, "ast-merge"),
            local_path: true,
            loaded: true,
          },
          {
            name: "json-merge",
            version: nil,
            path: nil,
            local_path: false,
            loaded: false,
          },
        ],
      }

      self_test_report = described_class::SelfTest::Reporter.summary(
        comparison,
        output_dir: File.join(root, "output"),
        templating_environment: snapshot,
        diff_count: 1,
        now: Time.utc(2026, 5, 14, 12, 0, 0)
      )
      expect(self_test_report).to include("**Score**: 25.0% (1/4 files unchanged)")
      expect(self_test_report).to include("**Divergence**: 75.0% (3/4 files changed, added, or missing)")
      expect(self_test_report).to include("## Changed Files (1)")
      expect(self_test_report).to include("## New Files (1)")
      expect(self_test_report).to include("## Not Templated - Unexpected (1)")
      expect(self_test_report).to include("<summary>Not Templated (1 files) - source-only files not produced by the template task</summary>")
      expect(self_test_report).to include("| ast-merge | 2.0.0 | local path |")
      expect(self_test_report).to include("| json-merge | _not loaded_ | not loaded |")

      run_report = described_class::TemplatingReport.render_markdown(
        project_root: root,
        snapshot: snapshot,
        run_started_at: Time.utc(2026, 5, 14, 12, 0, 0),
        finished_at: Time.utc(2026, 5, 14, 12, 1, 0),
        status: "failed",
        warnings: ["missing service", "missing service"],
        error: RuntimeError.new("boom"),
        template_diff: {added: ["new.md"], changed: ["README.md"], removed: ["old.md"]},
        template_commit_sha: "abc123"
      )
      expect(run_report).to include("# kettle-jem Templating Run Report")
      expect(run_report).to include("**Status**: `failed`")
      expect(run_report).to include("**Template commit**: `abc123`")
      expect(run_report.scan("- missing service").length).to eq(1)
      expect(run_report).to include("## Template File Changes")
      expect(run_report).to include("3 template file(s) since last run: 1 added, 1 changed, 1 removed")
      expect(run_report).to include("RuntimeError: boom")
    end
  end

  it "derives run stats from recipe reports" do
    stats = described_class.recipe_run_stats(
      [
        {changed: true, metadata: {destination_existed: false}},
        {changed: true, metadata: {destination_existed: true}},
        {changed: false, metadata: {destination_existed: true}},
        {changed: true, metadata: {delete_file: true, destination_existed: true}},
      ],
      diagnostics: [
        {kind: "plugin_file_change", path: "PLUGIN.md", action: "replace"},
      ]
    )

    expect(stats).to eq(
      recipes: 4,
      created: 1,
      pre_existing: 2,
      identical: 1,
      changed: 1,
      deleted: 1,
      plugin_file_changes: 1,
      summary: "recipes 4 created 1 pre_existing 2 identical 1 changed 1 deleted 1 plugin_file_changes 1"
    )
  end

  it "loads configured plugins and runs apply-time remaining-files hooks" do
    plugin_module = Module.new do
      class << self
        def register_kettle_jem_plugin(registrar)
          registrar.after_phase(:remaining_files) do |context:, phase:, phase_stats:, plugin_name:, **|
            path = File.join(context.project_root, "PLUGIN.md")
            File.write(path, "plugin=#{plugin_name}; phase=#{phase}; recipes=#{phase_stats.fetch(:recipe_count)}\n")
            context.helpers.record_template_result(path, :replace)
            context.out.report_detail("plugin hook ran")
          end
        end
      end
    end
    stub_const("Example::Plugin", plugin_module)
    allow(described_class::PluginLoader).to receive(:require).with("example/plugin").and_return(true)

    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-plugin-lifecycle", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          plugins:
            - example-plugin
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(File.exist?(File.join(root, "PLUGIN.md"))).to be(false)
      plan_lifecycle = plan.fetch(:diagnostics).find { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }
      expect(plan_lifecycle).to include(
        loaded_plugins: ["example-plugin"],
        callbacks_run: false
      )
      expect(plan.fetch(:run_stats).fetch(:plugin_file_changes)).to eq(0)

      apply = described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "PLUGIN.md"))).to include("plugin=example-plugin; phase=remaining_files; recipes=")
      expect(apply.fetch(:changed_files)).to include("PLUGIN.md")
      expect(apply.fetch(:run_stats).fetch(:plugin_file_changes)).to eq(1)
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_file_change",
        path: "PLUGIN.md",
        action: "replace"
      )
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "plugin hook ran"
      )
      apply_lifecycle = apply.fetch(:diagnostics).select { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }.last
      expect(apply_lifecycle).to include(
        loaded_plugins: ["example-plugin"],
        callbacks_run: true,
        active_runner_phase: "remaining_files"
      )
      expect(apply_lifecycle.fetch(:registered_hooks)).to contain_exactly(
        {
          plugin_name: "example-plugin",
          phase: "remaining_files",
          timing: "after"
        }
      )
    end
  end
end
