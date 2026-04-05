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
    it "returns [:NocovNode, nil] when there are no inner nodes" do
      expect(node.signature).to eq([:NocovNode, nil])
    end

    context "with a single inner node" do
      let(:inner_analysis) do
        Prism::Merge::FileAnalysis.new(<<~RUBY)
          # frozen_string_literal: true

          # :nocov:
          require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
          # :nocov:
        RUBY
      end

      it "delegates to the inner node's signature (enables cross-matching with bare nodes)" do
        # Promote via BlockDirectiveDetector so we get a real NocovNode
        nocov_node = inner_analysis.statements.find { |s| s.is_a?(described_class) }
        expect(nocov_node).not_to be_nil
        expect(nocov_node.nodes.length).to eq(1)

        # Inner node is the IfNode (modifier-if form)
        inner_sig = inner_analysis.generate_signature(nocov_node.nodes.first)
        expect(nocov_node.signature).to eq(inner_sig)
        expect(nocov_node.signature.first).not_to eq(:NocovNode)
      end
    end

    context "with multiple inner nodes" do
      let(:multi_analysis) do
        Prism::Merge::FileAnalysis.new(<<~RUBY)
          # :nocov:
          def unreachable_a; end
          def unreachable_b; end
          # :nocov:
        RUBY
      end

      it "returns [:nocov_multi, normalized_inner_content]" do
        nocov_node = multi_analysis.statements.find { |s| s.is_a?(described_class) }
        expect(nocov_node).not_to be_nil
        sig = nocov_node.signature
        expect(sig.first).to eq(:nocov_multi)
        expect(sig.last).to be_a(String)
      end
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

    context "when analysis has lines" do
      let(:source) { "# frozen_string_literal: true\ndef a; end\n# :nocov:\ndef b; end\n# :nocov:\n" }
      let(:analysis_with_lines) { Prism::Merge::FileAnalysis.new(source) }
      let(:node_with_offsets) do
        described_class.new(
          start_line: 3,
          end_line: 5,
          analysis: analysis_with_lines,
          nodes: [],
          start_marker: "# :nocov:",
          close_marker: "# :nocov:",
        )
      end

      it "returns a LocationWithOffsets with byte offsets" do
        loc = node_with_offsets.location
        expect(loc).to be_a(Prism::Merge::NocovNode::LocationWithOffsets)
      end

      it "start_offset equals sum of bytesize of all lines before start_line" do
        lines = source.lines
        expected_start = lines.take(2).sum(&:bytesize)
        expect(node_with_offsets.location.start_offset).to eq(expected_start)
      end

      it "end_offset equals sum of bytesize through end_line" do
        lines = source.lines
        expected_end = lines.take(5).sum(&:bytesize)
        expect(node_with_offsets.location.end_offset).to eq(expected_end)
      end

      it "cover? returns true for lines within the range" do
        loc = node_with_offsets.location
        expect(loc.cover?(3)).to be true
        expect(loc.cover?(4)).to be true
        expect(loc.cover?(5)).to be true
      end

      it "cover? returns false for lines outside the range" do
        loc = node_with_offsets.location
        expect(loc.cover?(2)).to be false
        expect(loc.cover?(6)).to be false
      end
    end

    context "when analysis is nil" do
      let(:node_no_analysis) do
        described_class.new(start_line: 1, end_line: 3, analysis: nil, nodes: [])
      end

      it "falls back to a plain Location struct" do
        loc = node_no_analysis.location
        expect(loc).to be_a(Prism::Merge::NocovNode::Location)
        expect(loc.start_line).to eq(1)
        expect(loc.end_line).to eq(3)
      end

      it "Location#cover? returns true for lines in range" do
        loc = node_no_analysis.location
        expect(loc.cover?(1)).to be true
        expect(loc.cover?(2)).to be true
        expect(loc.cover?(3)).to be true
      end

      it "Location#cover? returns false for lines outside range" do
        loc = node_no_analysis.location
        expect(loc.cover?(0)).to be false
        expect(loc.cover?(4)).to be false
      end
    end
  end

  describe "#leading_comments" do
    it "returns empty array when there are no inner nodes" do
      expect(node.leading_comments).to eq([])
    end

    it "returns empty array when analysis is nil" do
      n = described_class.new(start_line: 1, end_line: 2, analysis: nil, nodes: [])
      expect(n.leading_comments).to eq([])
    end

    context "when inner node has leading comments before start_line" do
      let(:source) do
        <<~RUBY
          # frozen_string_literal: true

          # Some description comment
          # :nocov:
          require "bundler/gem_tasks"
          # :nocov:
        RUBY
      end
      let(:full_analysis) { Prism::Merge::FileAnalysis.new(source) }

      it "returns comments from the inner node that precede the opening marker" do
        nocov = full_analysis.statements.find { |s| s.is_a?(described_class) }
        expect(nocov).not_to be_nil
        # The leading comment "# Some description comment" is on line 3,
        # which is before the opening # :nocov: on line 4
        comments = nocov.leading_comments
        expect(comments).to all(be_a(Prism::Comment))
        comment_texts = comments.map { |c| c.slice }
        expect(comment_texts).to include("# Some description comment")
      end
    end

    context "when inner node has no leading comments before start_line" do
      let(:source) do
        # No lines before the opening # :nocov:
        <<~RUBY
          # :nocov:
          require "bundler/gem_tasks"
          # :nocov:
        RUBY
      end
      let(:tight_analysis) { Prism::Merge::FileAnalysis.new(source) }

      it "returns empty array" do
        nocov = tight_analysis.statements.find { |s| s.is_a?(described_class) }
        expect(nocov).not_to be_nil
        expect(nocov.leading_comments).to eq([])
      end
    end
  end

  describe "#slice" do
    it "returns nil when analysis is nil" do
      n = described_class.new(start_line: 1, end_line: 2, analysis: nil, nodes: [])
      expect(n.slice).to be_nil
    end

    context "with analysis" do
      let(:source) { "# :nocov:\ndef unreachable; end\n# :nocov:\n" }
      let(:slice_analysis) { Prism::Merge::FileAnalysis.new(source) }

      it "returns the content lines of the nocov block" do
        nocov = slice_analysis.statements.find { |s| s.is_a?(described_class) }
        expect(nocov).not_to be_nil
        result = nocov.slice
        expect(result).to include("# :nocov:")
        expect(result).to include("def unreachable")
      end
    end
  end

  describe "#inspect" do
    it "includes class name and line range" do
      expect(node.inspect).to include("NocovNode")
      expect(node.inspect).to include("3..7")
    end
  end
end
