# frozen_string_literal: true

require "prism/merge"

RSpec.describe "Prism reproducible merge" do
  let(:fixtures_path) { File.expand_path("../fixtures/reproducible", __dir__) }
  let(:merger_class) { Prism::Merge::SmartMerger }
  let(:file_extension) { "rb" }

  describe "basic merge scenarios (destination wins by default)" do
    context "when a method is removed in destination" do
      it_behaves_like "a reproducible merge", "01_method_removed"
    end

    context "when a method is added in destination" do
      it_behaves_like "a reproducible merge", "02_method_added"
    end

    context "when an implementation is changed in destination" do
      it_behaves_like "a reproducible merge", "03_implementation_changed"
    end
  end

  describe "gemspec merge with freeze blocks (regression)" do
    let(:fixture_dir) { File.join(fixtures_path, "04_gemspec_duplication") }
    let(:template_fixture) { File.read(File.join(fixture_dir, "template.rb")) }
    let(:dest_fixture) { File.read(File.join(fixture_dir, "destination.rb")) }

    it "does not duplicate freeze blocks when template and dest have identical freeze block" do
      merger = Prism::Merge::SmartMerger.new(
        template_fixture,
        dest_fixture,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "kettle-dev",
      )
      merged = merger.merge

      # Template has 1 freeze block, dest has 2 (same first one + different second)
      # Expected: 2 freeze blocks total (the identical one should not be duplicated)
      freeze_count = merged.scan(/#\s*kettle-dev:freeze/i).length
      expect(freeze_count).to eq(2), "Expected 2 freeze blocks, got #{freeze_count}"

      # The dest-only freeze block (runtime dependencies) should be preserved
      expect(merged).to include("NOTE: This gem has \"runtime\" dependencies")
    end
  end
end
