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
end
