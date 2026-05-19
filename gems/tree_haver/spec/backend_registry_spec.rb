# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe TreeHaver::BackendRegistry do
  describe ".register_tag" do
    let(:tag_name) { :example_backend }
    let(:backend_name) { :example }

    it "registers tag metadata and exposes tag availability" do
      described_class.register_tag(tag_name, category: :backend, backend_name: backend_name) { true }

      expect(described_class.tag_registered?(tag_name)).to be(true)
      expect(described_class.registered_tags).to include(tag_name)
      expect(described_class.tags_by_category(:backend)).to include(tag_name)
      expect(described_class.tag_metadata(tag_name)).to include(
        category: :backend,
        backend_name: backend_name,
      )
      expect(described_class.tag_available?(tag_name)).to be(true)
    end

    it "defines dependency-tag availability methods after the RSpec helper is loaded" do
      require "tree_haver/rspec/dependency_tags"

      described_class.register_tag(:dynamic_example_backend, category: :backend, backend_name: :dynamic_example) { true }

      expect(TreeHaver::RSpec::DependencyTags.dynamic_example_available?).to be(true)
    end
  end
end
