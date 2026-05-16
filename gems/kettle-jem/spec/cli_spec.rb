# frozen_string_literal: true

require_relative "spec_helper"
require "stringio"

RSpec.describe Kettle::Jem::CLI do
  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path.to_s)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def run_cli(argv, env: {})
    out = StringIO.new
    err = StringIO.new
    status = described_class.run(argv, env: env, out: out, err: err)
    [status, out.string, err.string]
  end

  def tmp_root
    File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
  end

  it "prints help and version information" do
    help_status, help_out, help_err = run_cli(["--help"])
    version_status, version_out, version_err = run_cli(["version"])

    expect(help_status).to eq(0)
    expect(help_out).to include("kettle-jem plan")
    expect(help_err).to eq("")
    expect(version_status).to eq(0)
    expect(version_out).to eq("#{Kettle::Jem::Version::VERSION}\n")
    expect(version_err).to eq("")
  end

  it "plans a project and emits a machine-readable report" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })
      report_path = File.join(root, "tmp", "kettle-jem-plan.json")

      status, out, err = run_cli(["plan", root, "--accept", "--json", "--report", report_path])

      expect(status).to eq(0)
      expect(err).to eq("")
      payload = JSON.parse(out, symbolize_names: true)
      report = JSON.parse(File.read(report_path), symbolize_names: true)
      expect(payload.fetch(:mode)).to eq("plan")
      expect(payload.fetch(:decision_policy).fetch(:mode)).to eq("accept")
      expect(payload.fetch(:changed_files)).to include(".kettle-jem.yml")
      expect(report.fetch(:changed_files)).to eq(payload.fetch(:changed_files))
      expect(File.exist?(File.join(root, ".kettle-jem.yml"))).to be(false)
    end
  end

  it "applies a project through the template alias" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      status, out, err = run_cli(["template", root, "--force"])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("apply:")
      expect(File.exist?(File.join(root, ".kettle-jem.yml"))).to be(true)
    end
  end

  it "prints template manifest summaries" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      status, out, err = run_cli(["manifest", root])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to match(/template manifest: \d+ entries/)
    end
  end
end
