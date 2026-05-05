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

  it "plans and applies the RubyGems thin vertical slice" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-thin-slice", tmp_root) do |root|
      write_tree(root, fixture.fetch(:inputs).fetch(:files))

      plan = described_class.plan_project(root)
      expect(json_ready(plan[:facts])).to eq(json_ready(fixture.fetch(:expected).fetch(:facts)))
      expect(plan[:recipe_pack][:recipes].map { |recipe| recipe[:name] }).to eq(%w[
        readme_metadata
        changelog_unreleased
        generated_block_sync
      ])
      expect(plan[:changed_files]).to eq(fixture.fetch(:expected).fetch(:changed_files))
      expect(plan[:recipe_reports].map { |report| report[:request_envelope][:kind] }.uniq).to eq(["content_recipe_execution_request"])
      expect(plan[:recipe_reports].map { |report| report[:report_envelope][:kind] }.uniq).to eq(["content_recipe_execution_report"])

      apply = described_class.apply_project(root)
      expect(apply[:changed_files]).to eq(fixture.fetch(:expected).fetch(:changed_files))
      expect(project_files(root, fixture.fetch(:expected).fetch(:files).keys.map(&:to_s))).to eq(fixture.fetch(:expected).fetch(:files))
    end
  end
end
