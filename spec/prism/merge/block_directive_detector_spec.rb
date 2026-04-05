# frozen_string_literal: true

RSpec.describe Prism::Merge::BlockDirectiveDetector do
  let(:freeze_token) { "prism-merge" }
  let(:nocov_token) { described_class::NOCOV_TOKEN }

  def lines_from(source)
    source.lines
  end

  describe "#detect_spans" do
    context "with freeze blocks" do
      it "detects a simple freeze block" do
        lines = lines_from(<<~RUBY)
          # prism-merge:freeze
          CONST = 1
          # prism-merge:unfreeze
        RUBY

        detector = described_class.new(lines, freeze_token: freeze_token)
        spans = detector.detect_spans

        expect(spans.size).to eq(1)
        expect(spans.first.kind).to eq(:freeze)
        expect(spans.first.start_line).to eq(1)
        expect(spans.first.end_line).to eq(3)
      end

      it "returns empty when no freeze token configured" do
        lines = lines_from(<<~RUBY)
          # prism-merge:freeze
          CONST = 1
          # prism-merge:unfreeze
        RUBY

        detector = described_class.new(lines, freeze_token: nil)
        expect(detector.detect_spans).to be_empty
      end

      it "warns and ignores unmatched unfreeze" do
        lines = lines_from(<<~RUBY)
          CONST = 1
          # prism-merge:unfreeze
        RUBY

        detector = described_class.new(lines, freeze_token: freeze_token)
        expect { detector.detect_spans }.to output(/unmatched/).to_stderr
        expect(detector.detect_spans).to be_empty
      end

      it "warns and ignores unclosed freeze" do
        lines = lines_from(<<~RUBY)
          # prism-merge:freeze
          CONST = 1
        RUBY

        detector = described_class.new(lines, freeze_token: freeze_token)
        expect { detector.detect_spans }.to output(/unclosed/).to_stderr
        expect(detector.detect_spans).to be_empty
      end
    end

    context "with nocov blocks" do
      it "detects a simple nocov block" do
        lines = lines_from(<<~RUBY)
          # :nocov:
          def branch
          end
          # :nocov:
        RUBY

        detector = described_class.new(lines)
        spans = detector.detect_spans

        expect(spans.size).to eq(1)
        expect(spans.first.kind).to eq(:nocov)
        expect(spans.first.start_line).to eq(1)
        expect(spans.first.end_line).to eq(4)
      end

      it "detects multiple separate nocov blocks" do
        lines = lines_from(<<~RUBY)
          # :nocov:
          def a; end
          # :nocov:
          code
          # :nocov:
          def b; end
          # :nocov:
        RUBY

        detector = described_class.new(lines)
        spans = detector.detect_spans

        expect(spans.size).to eq(2)
        expect(spans[0].start_line).to eq(1)
        expect(spans[0].end_line).to eq(3)
        expect(spans[1].start_line).to eq(5)
        expect(spans[1].end_line).to eq(7)
      end

      it "warns and ignores unclosed nocov" do
        lines = lines_from(<<~RUBY)
          # :nocov:
          def a; end
        RUBY

        detector = described_class.new(lines)
        expect { detector.detect_spans }.to output(/unclosed/).to_stderr
      end
    end

    context "with nested blocks (freeze inside nocov)" do
      it "returns both spans sorted by start_line" do
        lines = lines_from(<<~RUBY)
          # :nocov:
          # prism-merge:freeze
          CONST = 1
          # prism-merge:unfreeze
          # :nocov:
        RUBY

        detector = described_class.new(lines, freeze_token: freeze_token)
        spans = detector.detect_spans

        expect(spans.size).to eq(2)
        outer = spans.find { |s| s.kind == :nocov }
        inner = spans.find { |s| s.kind == :freeze }
        expect(outer.start_line).to eq(1)
        expect(outer.end_line).to eq(5)
        expect(inner.start_line).to eq(2)
        expect(inner.end_line).to eq(4)
      end
    end

    context "with crossing blocks" do
      it "excludes both crossing spans and emits a warning" do
        lines = lines_from(<<~RUBY)
          # prism-merge:freeze
          # :nocov:
          code
          # prism-merge:unfreeze
          other
          # :nocov:
        RUBY

        detector = described_class.new(lines, freeze_token: freeze_token)
        expect { @spans = detector.detect_spans }.to output(/offset-overlapping/).to_stderr
        expect(@spans).to be_empty
      end
    end
  end

  describe "#promote_spans_to_nodes" do
    let(:analysis) do
      Prism::Merge::FileAnalysis.new(<<~RUBY)
        CONST = 1
        def foo; end
      RUBY
    end

    it "returns statements unchanged when no spans" do
      lines = lines_from("CONST = 1\n")
      detector = described_class.new(lines)
      stmts = analysis.statements
      result = detector.promote_spans_to_nodes(stmts, [], analysis: analysis)
      expect(result).to eq(stmts)
    end

    it "promotes a freeze span to a FreezeNode" do
      source = <<~RUBY
        # prism-merge:freeze
        CONST = 1
        # prism-merge:unfreeze
        def foo; end
      RUBY
      local_analysis = Prism::Merge::FileAnalysis.new(source)
      lines = lines_from(source)
      detector = described_class.new(lines, freeze_token: freeze_token)
      spans = detector.detect_spans
      stmts = local_analysis.statements

      result = detector.promote_spans_to_nodes(stmts, spans, analysis: local_analysis)

      freeze_node = result.find { |n| n.is_a?(Prism::Merge::FreezeNode) }
      expect(freeze_node).not_to be_nil
      expect(freeze_node.start_line).to eq(1)
      expect(freeze_node.end_line).to eq(3)
    end

    it "promotes a nocov span to a NocovNode" do
      source = <<~RUBY
        code = 1
        # :nocov:
        def unreachable; end
        # :nocov:
      RUBY
      local_analysis = Prism::Merge::FileAnalysis.new(source)
      lines = lines_from(source)
      detector = described_class.new(lines)
      spans = detector.detect_spans
      stmts = local_analysis.statements

      result = detector.promote_spans_to_nodes(stmts, spans, analysis: local_analysis)

      nocov_node = result.find { |n| n.is_a?(Prism::Merge::NocovNode) }
      expect(nocov_node).not_to be_nil
      expect(nocov_node.kind).to eq(:nocov)
    end
  end
end
