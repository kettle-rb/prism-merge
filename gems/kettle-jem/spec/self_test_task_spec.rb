# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Kettle::Jem::Tasks::SelfTestTask do
  def write_file(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it "validates a destination project against template output and writes reports" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest", tmp_root) do |root|
      write_file(root, "README.md", "before\n")
      allow(Kettle::Jem).to receive(:apply_project) do |project_root, **|
        File.write(File.join(project_root, "README.md"), "after\n")
        {mode: "apply"}
      end

      result = described_class.run(project_root: root, min_divergence_threshold: 100)

      expect(result.fetch(:mode)).to eq("selftest")
      expect(result.fetch(:comparison).fetch(:changed)).to eq(["README.md"])
      expect(result.fetch(:divergence)).to eq(100.0)
      expect(File).to exist(File.join(root, "tmp", "template_test", "report", "before.json"))
      expect(File).to exist(File.join(root, "tmp", "template_test", "report", "after.json"))
      expect(File.read(result.fetch(:report_path))).to include("## Drift Analysis")
    end
  end

  it "fails when divergence exceeds the configured threshold after writing the report" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest", tmp_root) do |root|
      write_file(root, "README.md", "before\n")
      allow(Kettle::Jem).to receive(:apply_project) do |project_root, **|
        File.write(File.join(project_root, "README.md"), "after\n")
        {mode: "apply"}
      end

      expect {
        described_class.run(project_root: root, min_divergence_threshold: 0)
      }.to raise_error(Kettle::Jem::Error, /divergence 100\.0% exceeds threshold 0\.0%/)

      expect(File).to exist(File.join(root, "tmp", "template_test", "report", "summary.md"))
    end
  end

  it "filters generated runtime artifacts from selftest comparisons" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest-artifacts", tmp_root) do |root|
      write_file(root, "README.md", "stable\n")
      allow(Kettle::Jem).to receive(:apply_project) do |project_root, **|
        write_file(project_root, "tmp/kettle-jem/templating-report-20260516-120000-000000-1234.md", "run report\n")
        write_file(project_root, "gemfiles/modular/shunted.gemfile", "# generated shunt\n")
        write_file(project_root, "unexpected.txt", "real addition\n")
        {mode: "apply"}
      end

      result = described_class.run(project_root: root, min_divergence_threshold: 100)

      expect(result.fetch(:comparison).fetch(:added)).to eq(["unexpected.txt"])
    end
  end

  it "runs a real scaffold selftest through the template apply path" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest-real-scaffold", tmp_root) do |root|
      write_file(root, "example.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "example"
          spec.summary = "Example"
        end
      RUBY
      write_file(root, ".kettle-jem.yml", <<~YAML)
        templates:
          root: template
          apply: true
          entries:
            - README.md
      YAML
      write_file(root, "README.md", "# Before\n")
      write_file(root, "template/README.md.example", "# Example\n")

      result = described_class.run(project_root: root, min_divergence_threshold: 100)

      expect(result.fetch(:comparison).fetch(:changed)).to include("README.md")
      expect(result.fetch(:output_root)).to start_with(File.join(root, "tmp", "template_test", "output"))
      expect(File.read(File.join(result.fetch(:output_root), "README.md"))).to include("# Example")
      expect(File).to exist(result.fetch(:report_path))
    end
  end
end
