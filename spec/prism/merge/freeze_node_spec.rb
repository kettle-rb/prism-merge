# frozen_string_literal: true

RSpec.describe Prism::Merge::FreezeNode do
  let(:analysis) do
    Prism::Merge::FileAnalysis.new(<<~RUBY)
      # frozen_string_literal: true
      def a; end
    RUBY
  end

  # Prism::Merge::FreezeNode has a specialized constructor that requires analysis and nodes
  # Use shared examples with appropriate factory
  it_behaves_like "Ast::Merge::FreezeNodeBase" do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      ->(start_line:, end_line:, **opts) {
        freeze_node_class.new(start_line: start_line, end_line: end_line, analysis: analysis, nodes: [], **opts)
      }
    end
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

  describe "overlapping node validation" do
    let(:multiline_analysis) do
      Prism::Merge::FileAnalysis.new(<<~RUBY)
        # frozen_string_literal: true

        # prism-merge:freeze
        CONST = 1
        # prism-merge:unfreeze

        def method
          "body"
        end
      RUBY
    end

    it "allows class nodes that fully encompass freeze block" do
      # This tests line 117-118 where valid_encompass is true for ClassNode
      encompass_analysis = Prism::Merge::FileAnalysis.new(<<~RUBY)
        # frozen_string_literal: true

        class MyClass
          # prism-merge:freeze
          CONST = 1
          # prism-merge:unfreeze
        end
      RUBY

      # Should not raise - class encompassing freeze block is valid
      expect(encompass_analysis.statements).not_to be_empty
    end

    it "allows module nodes that fully encompass freeze block" do
      encompass_analysis = Prism::Merge::FileAnalysis.new(<<~RUBY)
        # frozen_string_literal: true

        module MyModule
          # prism-merge:freeze
          CONST = 1
          # prism-merge:unfreeze
        end
      RUBY

      expect(encompass_analysis.statements).not_to be_empty
    end

    it "raises for unsupported node types that encompass freeze block" do
      # Tests line 121 else branch - encompasses && !valid_encompass
      # Create a mock node that fully encompasses the freeze block but is not a valid type
      # (not ClassNode, ModuleNode, DefNode, etc.)
      location = Struct.new(:start_line, :end_line).new(1, 10)
      encompassing_node = double("EncompassingIfNode", location: location)
      # Make it NOT a valid encompassing type by returning false for all valid types
      allow(encompassing_node).to receive(:is_a?) do |klass|
        false # Not ClassNode, ModuleNode, DefNode, etc.
      end
      allow(encompassing_node).to receive_message_chain(:class, :name).and_return("Prism::IfNode")

      # Freeze block is lines 3-5, encompassing node is 1-10
      expect {
        described_class.new(
          start_line: 3,
          end_line: 5,
          analysis: analysis,
          nodes: [],
          overlapping_nodes: [encompassing_node],
        )
      }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError)
    end

    it "reports overlap type correctly in error message" do
      # Test line 135 - overlap type description
      location = Struct.new(:start_line, :end_line).new(1, 5)
      overlapping_node = double("OverlappingNode", location: location)
      allow(overlapping_node).to receive(:is_a?).and_return(false)
      allow(overlapping_node).to receive_message_chain(:class, :name).and_return("Prism::IfNode")

      expect {
        described_class.new(
          start_line: 3,
          end_line: 4,
          analysis: analysis,
          nodes: [],
          overlapping_nodes: [overlapping_node],
        )
      }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError) do |error|
        expect(error.message).to include("starts before freeze block")
      end
    end

    it "reports end overlap type correctly" do
      # Test line 135 else branch - node starts inside and ends after
      location = Struct.new(:start_line, :end_line).new(3, 10)
      overlapping_node = double("OverlappingNode", location: location)
      allow(overlapping_node).to receive(:is_a?).and_return(false)
      allow(overlapping_node).to receive_message_chain(:class, :name).and_return("Prism::DefNode")

      expect {
        described_class.new(
          start_line: 2,
          end_line: 5,
          analysis: analysis,
          nodes: [],
          overlapping_nodes: [overlapping_node],
        )
      }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError) do |error|
        expect(error.message).to include("starts inside freeze block")
      end
    end
  end
end
