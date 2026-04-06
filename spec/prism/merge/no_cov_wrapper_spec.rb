# frozen_string_literal: true

RSpec.describe Prism::Merge::NoCovWrapper do
  let(:inner_source) { "def foo; end\n" }
  let(:inner_analysis) { Prism::Merge::FileAnalysis.new(inner_source) }
  let(:prism_node) { inner_analysis.statements.first }
  let(:wrapper) { described_class.new(prism_node) }

  describe "#kind" do
    it "returns :nocov" do
      expect(wrapper.kind).to eq(:nocov)
    end
  end

  describe "#unwrap" do
    it "returns the wrapped node" do
      expect(wrapper.unwrap).to eq(prism_node)
    end
  end

  describe "#block_directive?" do
    it "returns true" do
      expect(wrapper.block_directive?).to be true
    end
  end

  describe "#nocov_wrapper?" do
    it "returns true" do
      expect(wrapper.nocov_wrapper?).to be true
    end
  end

  describe "#nocov_node?" do
    it "returns false (wrapper is not a NocovNode block)" do
      expect(wrapper.nocov_node?).to be false
    end
  end

  describe "#merge_policy" do
    it "returns nil (follows file preference)" do
      expect(wrapper.merge_policy).to be_nil
    end
  end

  describe "#children" do
    it "returns empty array" do
      expect(wrapper.children).to eq([])
    end
  end

  describe "#start_line / #end_line" do
    it "delegates to the wrapped node's location" do
      expect(wrapper.start_line).to eq(prism_node.location.start_line)
      expect(wrapper.end_line).to eq(prism_node.location.end_line)
    end
  end

  describe "#location" do
    it "delegates to the wrapped node" do
      expect(wrapper.location).to eq(prism_node.location)
    end
  end

  describe "#slice" do
    it "delegates to the wrapped node" do
      expect(wrapper.slice).to eq(prism_node.slice)
    end
  end

  describe "default merge_type" do
    it "is :nocov" do
      expect(wrapper.merge_type).to eq(:nocov)
    end
  end

  describe "custom merge_type" do
    it "is preserved from constructor" do
      w = described_class.new(prism_node, :custom)
      expect(w.merge_type).to eq(:custom)
    end
  end
end
