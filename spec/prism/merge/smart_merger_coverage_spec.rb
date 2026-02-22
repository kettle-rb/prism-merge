# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "#merge_with_debug" do
    it "returns debug info with statement counts" do
      template = "def hello; end"
      dest = "def hello; end"
      merger = described_class.new(template, dest)
      result = merger.merge_with_debug

      expect(result[:debug][:template_statements]).to eq(1)
      expect(result[:debug][:dest_statements]).to eq(1)
      expect(result[:debug][:preference]).to eq(:destination)
      expect(result[:debug][:add_template_only_nodes]).to be(false)
      expect(result[:debug][:freeze_token]).to eq("prism-merge")
    end

    it "returns statistics from the merge result" do
      template = "def hello; end"
      dest = "def hello; end"
      merger = described_class.new(template, dest)
      result = merger.merge_with_debug

      expect(result[:statistics]).to be_a(Hash)
      expect(result[:statistics].values).to all(be_a(Integer))
    end
  end

  describe "parse error handling" do
    it "raises TemplateParseError for truly invalid template syntax" do
      # Prism is a recoverable parser, so many invalid syntaxes still parse.
      # The base class parse_and_analyze catches valid? == false.
      invalid_template = "def ("
      valid_dest = "x = 1"

      expect {
        described_class.new(invalid_template, valid_dest).merge
      }.to raise_error(Prism::Merge::TemplateParseError)
    end

    it "raises DestinationParseError for truly invalid destination syntax" do
      valid_template = "x = 1"
      invalid_dest = "def ("

      expect {
        described_class.new(valid_template, invalid_dest).merge
      }.to raise_error(Prism::Merge::DestinationParseError)
    end
  end

  describe "emit_dest_prefix_lines" do
    it "preserves magic comment and blank line before first node" do
      template = "x = 1"
      dest = "# frozen_string_literal: true\n\nx = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("# frozen_string_literal: true\n")
      expect(result).to include("x = 1")
    end

    it "preserves multiple prefix lines (encoding + frozen_string_literal)" do
      template = "x = 1"
      dest = "# encoding: utf-8\n# frozen_string_literal: true\n\nx = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("# encoding: utf-8\n# frozen_string_literal: true\n")
      expect(result).to include("x = 1")
    end

    it "handles dest where first node starts on line 1 (no prefix)" do
      template = "x = 1"
      dest = "x = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("x = 1")
    end
  end

  describe "emit_dest_gap_lines" do
    it "preserves blank lines between top-level blocks" do
      template = <<~RUBY
        def foo
          1
        end

        def bar
          2
        end
      RUBY

      dest = <<~RUBY
        def foo
          1
        end

        def bar
          2
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      # Should preserve the blank line between the two methods
      expect(result).to include("end\n\ndef bar")
    end

    it "preserves blank lines between blocks with leading comments" do
      template = <<~RUBY
        # Comment A
        def foo
          1
        end

        # Comment B
        def bar
          2
        end
      RUBY

      dest = <<~RUBY
        # Comment A
        def foo
          1
        end

        # Comment B
        def bar
          2
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      # The blank line between `end` and `# Comment B` should be preserved
      expect(result).to include("end\n\n# Comment B")
    end

    it "preserves multiple blank lines between blocks" do
      template = <<~RUBY
        x = 1


        y = 2
      RUBY

      dest = <<~RUBY
        x = 1


        y = 2
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      # At least one blank line should separate x = 1 and y = 2
      lines = result.split("\n")
      x_idx = lines.index { |l| l.include?("x = 1") }
      y_idx = lines.index { |l| l.include?("y = 2") }
      expect(y_idx - x_idx).to be > 1
    end
  end

  describe "preference_for_node with Hash preference and node_typing" do
    it "uses typed dest merge_type when template is not typed" do
      template = <<~RUBY
        gem "foo"
        gem "bar"
      RUBY

      dest = <<~RUBY
        gem "foo"
        gem "bar"
      RUBY

      # node_typing that only types "bar" as :special
      node_typing = {
        CallNode: ->(node) {
          if node.respond_to?(:arguments) &&
              node.arguments&.arguments&.first.respond_to?(:unescaped) &&
              node.arguments.arguments.first.unescaped == "bar"
            Ast::Merge::NodeTyping.with_merge_type(node, :special)
          end
        },
      }

      merger = described_class.new(
        template,
        dest,
        preference: {default: :destination, special: :template},
        node_typing: node_typing,
      )

      result = merger.merge
      expect(result).to include('gem "foo"')
      expect(result).to include('gem "bar"')
    end

    it "falls back to default_preference when merge_type not in Hash" do
      template = <<~RUBY
        gem "foo"
      RUBY

      dest = <<~RUBY
        gem "foo"
      RUBY

      node_typing = {
        CallNode: ->(node) {
          Ast::Merge::NodeTyping.with_merge_type(node, :unknown_type)
        },
      }

      merger = described_class.new(
        template,
        dest,
        preference: {default: :destination},
        node_typing: node_typing,
      )

      result = merger.merge
      expect(result).to include('gem "foo"')
    end
  end

  describe "add_comment_node_to_result fallback branches" do
    it "handles comment-only files where nodes respond to text" do
      template = "# Just a comment\n# Another comment\n"
      dest = "# Just a comment\n# Another comment\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("# Just a comment")
      expect(result).to include("# Another comment")
    end

    it "handles comment-only files with empty lines between comments" do
      template = "# First\n\n# Second\n"
      dest = "# First\n\n# Second\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("# First")
      expect(result).to include("# Second")
    end

    it "handles comment-only template merged with comment-only dest" do
      template = "# Template only\n"
      dest = "# Dest only\n"

      merger = described_class.new(template, dest, preference: :destination)
      result = merger.merge

      expect(result).to include("# Dest only")
    end
  end

  describe "protected methods" do
    let(:merger) { described_class.new("x = 1", "x = 1") }

    it "result_class returns MergeResult" do
      expect(merger.send(:result_class)).to eq(Prism::Merge::MergeResult)
    end

    it "aligner_class returns nil" do
      expect(merger.send(:aligner_class)).to be_nil
    end

    it "resolver_class returns nil" do
      expect(merger.send(:resolver_class)).to be_nil
    end

    it "default_freeze_token returns prism-merge" do
      expect(merger.send(:default_freeze_token)).to eq("prism-merge")
    end

    it "analysis_class returns FileAnalysis" do
      expect(merger.send(:analysis_class)).to eq(Prism::Merge::FileAnalysis)
    end
  end

  describe "build_result" do
    it "passes template_analysis and dest_analysis to MergeResult" do
      merger = described_class.new("x = 1", "y = 2")
      result = merger.result

      expect(result).to be_a(Prism::Merge::MergeResult)
      expect(result.template_analysis).to eq(merger.template_analysis)
      expect(result.dest_analysis).to eq(merger.dest_analysis)
    end
  end

  describe "merge with prefix lines and gap lines combined" do
    it "preserves magic comment prefix AND inter-block gaps" do
      template = <<~RUBY
        def foo
          1
        end

        def bar
          2
        end
      RUBY

      dest = <<~RUBY
        # frozen_string_literal: true

        def foo
          1
        end

        def bar
          2
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("# frozen_string_literal: true\n")
      expect(result).to include("end\n\ndef bar")
    end
  end

  describe "node_contains_freeze_blocks?" do
    it "returns false when freeze_token is nil" do
      merger = described_class.new("x = 1", "x = 1", freeze_token: nil)
      node = merger.template_analysis.statements.first

      expect(merger.send(:node_contains_freeze_blocks?, node)).to be(false)
    end
  end
end
