# frozen_string_literal: true

RSpec.describe Prism::Merge::NocovNode do
  let(:analysis) do
    Prism::Merge::FileAnalysis.new(<<~RUBY)
      # frozen_string_literal: true
      def a; end
    RUBY
  end

  let(:node) do
    described_class.new(
      start_line: 3,
      end_line: 7,
      analysis: analysis,
      nodes: [],
      start_marker: "# :nocov:",
      close_marker: "# :nocov:",
    )
  end

  describe "#kind" do
    it "returns :nocov" do
      expect(node.kind).to eq(:nocov)
    end
  end

  describe "#merge_policy" do
    it "returns nil (follows file preference)" do
      expect(node.merge_policy).to be_nil
    end
  end

  describe "#block_directive?" do
    it "returns true" do
      expect(node.block_directive?).to be true
    end
  end

  describe "#nocov_directive?" do
    it "returns true" do
      expect(node.nocov_directive?).to be true
    end
  end

  describe "#freeze_directive?" do
    it "returns false" do
      expect(node.freeze_directive?).to be false
    end
  end

  describe "#line_range" do
    it "returns the start..end range" do
      expect(node.line_range).to eq(3..7)
    end
  end

  describe "#covers_line?" do
    it "returns true for lines within range" do
      expect(node.covers_line?(3)).to be true
      expect(node.covers_line?(5)).to be true
      expect(node.covers_line?(7)).to be true
    end

    it "returns false for lines outside range" do
      expect(node.covers_line?(2)).to be false
      expect(node.covers_line?(8)).to be false
    end
  end

  describe "#signature" do
    it "returns an Array starting with :NocovNode" do
      expect(node.signature).to be_an(Array)
      expect(node.signature.first).to eq(:NocovNode)
    end
  end

  describe "#children" do
    it "returns the nodes array" do
      inner = double("inner_node")
      n = described_class.new(start_line: 1, end_line: 2, analysis: analysis, nodes: [inner])
      expect(n.children).to eq([inner])
    end

    it "returns empty array by default" do
      expect(node.children).to eq([])
    end
  end

  describe "#nocov_node?" do
    it "returns true" do
      expect(node.nocov_node?).to be true
    end
  end

  describe "#location" do
    it "returns a location with start_line and end_line" do
      expect(node.location.start_line).to eq(3)
      expect(node.location.end_line).to eq(7)
    end
  end

  describe "#inspect" do
    it "includes class name and line range" do
      expect(node.inspect).to include("NocovNode")
      expect(node.inspect).to include("3..7")
    end
  end
end
