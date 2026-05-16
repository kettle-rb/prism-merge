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
end
