# frozen_string_literal: true

RSpec.describe Prism::Merge::FreezeNode do
  let(:analysis) do
    Prism::Merge::FileAnalysis.new(<<~RUBY)
      # frozen_string_literal: true
      def a; end
    RUBY
  end

  it "computes signature and slice" do
    node = described_class.new(start_line: 1, end_line: 1, analysis: analysis, nodes: [])
    expect(node.signature).to be_an(Array)
    expect(node.slice).to be_a(String)
    expect(node.freeze_node?).to be true
  end

  it "raises InvalidStructureError for partially overlapping nodes" do
    # Create a mock node that partially overlaps with freeze block
    location = Struct.new(:start_line, :end_line).new(0, 3)
    overlapping_node = double("OverlappingNode", location: location)
    # is_a? check for ClassNode/ModuleNode will return false for double
    allow(overlapping_node).to receive(:is_a?).and_return(false)

    expect {
      described_class.new(
        start_line: 1,
        end_line: 2,
        analysis: analysis,
        nodes: [],
        overlapping_nodes: [overlapping_node],
      )
    }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError)
  end
end
