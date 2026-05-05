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

      plan = described_class.plan_project(root)
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

      apply = described_class.apply_project(root)
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

      plan = described_class.plan_project(root)
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
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
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

      plan = described_class.plan_project(root)
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_files)).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe.fetch(:name) }
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_opencollective_yml")
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_github_workflows_opencollective_yml")
      expect(recipe_names).not_to include("github_actions_workflow_snippets_github_workflows_opencollective_yml")
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

      apply = described_class.apply_project(root)
      expect(apply[:changed_files]).to include(".opencollective.yml", ".github/workflows/opencollective.yml")
      expect(File).not_to exist(File.join(root, ".opencollective.yml"))
      expect(File).not_to exist(File.join(root, ".github/workflows/opencollective.yml"))
    end
  end
end
