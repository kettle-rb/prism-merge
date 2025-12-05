# frozen_string_literal: true

RSpec.describe Prism::Merge::MergeResult do
  describe "#initialize" do
    it "creates an empty result" do
      result = described_class.new

      expect(result.lines).to be_empty
      expect(result.line_metadata).to be_empty
    end
  end

  describe "#add_line" do
    let(:result) { described_class.new }

    it "adds a line with decision and metadata" do
      result.add_line("puts 'hello'", decision: :kept_template, template_line: 5)

      expect(result.lines).to eq(["puts 'hello'"])
      expect(result.line_metadata.length).to eq(1)

      metadata = result.line_metadata.first
      expect(metadata[:decision]).to eq(:kept_template)
      expect(metadata[:template_line]).to eq(5)
      expect(metadata[:dest_line]).to be_nil
      expect(metadata[:result_line]).to eq(1)
    end

    it "adds a line from destination" do
      result.add_line("VERSION = '1.0'", decision: :kept_destination, dest_line: 10)

      metadata = result.line_metadata.first
      expect(metadata[:decision]).to eq(:kept_destination)
      expect(metadata[:dest_line]).to eq(10)
      expect(metadata[:template_line]).to be_nil
    end

    it "adds a line with both source references" do
      result.add_line("# frozen", decision: :exact_match, template_line: 1, dest_line: 1)

      metadata = result.line_metadata.first
      expect(metadata[:template_line]).to eq(1)
      expect(metadata[:dest_line]).to eq(1)
    end

    it "adds a line with comment" do
      result.add_line("gem 'rails'", decision: :kept_destination, dest_line: 5, comment: "Matched by signature")

      metadata = result.line_metadata.first
      expect(metadata[:comment]).to eq("Matched by signature")
    end

    it "tracks result line numbers correctly for multiple lines" do
      result.add_line("line 1", decision: :kept_template, template_line: 1)
      result.add_line("line 2", decision: :kept_template, template_line: 2)
      result.add_line("line 3", decision: :kept_destination, dest_line: 5)

      expect(result.line_metadata[0][:result_line]).to eq(1)
      expect(result.line_metadata[1][:result_line]).to eq(2)
      expect(result.line_metadata[2][:result_line]).to eq(3)
    end
  end

  describe "#add_lines_from" do
    let(:result) { described_class.new }

    it "adds multiple lines from template" do
      lines = ["def hello", "  puts 'world'", "end"]
      result.add_lines_from(lines, decision: :kept_template, source: :template, start_line: 10)

      expect(result.lines).to eq(lines)
      expect(result.line_metadata.length).to eq(3)

      expect(result.line_metadata[0][:template_line]).to eq(10)
      expect(result.line_metadata[1][:template_line]).to eq(11)
      expect(result.line_metadata[2][:template_line]).to eq(12)

      result.line_metadata.each do |meta|
        expect(meta[:decision]).to eq(:kept_template)
        expect(meta[:dest_line]).to be_nil
      end
    end

    it "adds multiple lines from destination" do
      lines = ["class Test", "end"]
      result.add_lines_from(lines, decision: :kept_destination, source: :destination, start_line: 20)

      expect(result.line_metadata[0][:dest_line]).to eq(20)
      expect(result.line_metadata[1][:dest_line]).to eq(21)

      result.line_metadata.each do |meta|
        expect(meta[:decision]).to eq(:kept_destination)
        expect(meta[:template_line]).to be_nil
      end
    end

    it "adds lines with comment" do
      lines = ["# comment", "code"]
      result.add_lines_from(lines, decision: :appended, source: :destination, start_line: 1, comment: "Dest-only")

      result.line_metadata.each do |meta|
        expect(meta[:comment]).to eq("Dest-only")
      end
    end
  end

  describe "#add_node" do
    let(:result) { described_class.new }
    let(:template_content) do
      <<~RUBY
        # Leading comment
        def example # inline comment
          puts "hello"
        end
      RUBY
    end
    let(:analysis) { Prism::Merge::FileAnalysis.new(template_content) }

    it "adds node with leading comments" do
      node_info = analysis.nodes_with_comments.first

      result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: analysis)

      # Should include leading comment
      expect(result.lines).to include("# Leading comment")

      # Should include method definition
      expect(result.lines.join("\n")).to include("def example")
      expect(result.lines.join("\n")).to include("puts \"hello\"")
      expect(result.lines.join("\n")).to include("end")
    end

    it "adds node with inline comments" do
      node_info = analysis.nodes_with_comments.first

      result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: analysis)

      # Should include inline comment
      result_text = result.lines.join("\n")
      expect(result_text).to include("# inline comment")
    end

    it "adds node from destination with correct metadata" do
      dest_content = "def dest_method\n  puts 'dest'\nend"
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)
      node_info = dest_analysis.nodes_with_comments.first

      result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: dest_analysis)

      result.line_metadata.each do |meta|
        expect(meta[:decision]).to eq(:kept_destination)
        expect(meta[:dest_line]).not_to be_nil
        expect(meta[:template_line]).to be_nil
      end
    end

    it "handles nodes with multiple inline comments" do
      content = "VERSION = '1.0' # main version # important"
      analysis = Prism::Merge::FileAnalysis.new(content)
      node_info = analysis.nodes_with_comments.first

      result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: analysis)

      result_text = result.lines.join("\n")
      # Both inline comments should be preserved
      expect(result_text).to include("# main version")
      expect(result_text).to include("# important")
    end

    it "handles nodes without comments" do
      content = "VERSION = '1.0'"
      analysis = Prism::Merge::FileAnalysis.new(content)
      node_info = analysis.nodes_with_comments.first

      result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: analysis)

      expect(result.lines).to eq(["VERSION = '1.0'"])
    end

    context "without source_analysis (fallback path)" do
      it "adds node using node.slice when source_analysis is nil" do
        content = "  def indented_method\n    puts 'test'\n  end"
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        # Call without source_analysis - uses fallback node.slice path
        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: nil)

        # Should include the method (loses leading indentation with node.slice)
        result_text = result.lines.join("\n")
        expect(result_text).to include("def indented_method")
        expect(result_text).to include("puts 'test'")
        expect(result_text).to include("end")
      end

      it "adds leading comments using comment.slice when source_analysis is nil" do
        content = "  # A leading comment\n  def my_method\n    'result'\n  end"
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: nil)

        # Should include the comment (from comment.slice.rstrip)
        result_text = result.lines.join("\n")
        expect(result_text).to include("# A leading comment")
        expect(result.line_metadata.first[:dest_line]).not_to be_nil
      end

      it "handles inline comments using node.slice fallback" do
        content = "CONST = 'value' # inline comment"
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: nil)

        result_text = result.lines.join("\n")
        expect(result_text).to include("CONST = 'value'")
        expect(result_text).to include("# inline comment")
      end

      it "handles multi-line nodes using node.slice fallback" do
        content = "class MyClass\n  attr_reader :name\nend"
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: nil)

        expect(result.lines.length).to eq(3)
        expect(result.lines[0]).to eq("class MyClass")
        expect(result.lines[1]).to eq("  attr_reader :name")
        expect(result.lines[2]).to eq("end")

        # Verify line numbers are tracked correctly
        expect(result.line_metadata[0][:dest_line]).to eq(1)
        expect(result.line_metadata[1][:dest_line]).to eq(2)
        expect(result.line_metadata[2][:dest_line]).to eq(3)
      end

      it "handles nodes without any comments using fallback" do
        content = "simple_call"
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: nil)

        expect(result.lines).to eq(["simple_call"])
        expect(result.line_metadata.first[:template_line]).to eq(1)
      end
    end
  end

  describe "#to_s" do
    let(:result) { described_class.new }

    it "returns empty string with newline for empty result" do
      expect(result.to_s).to eq("\n")
    end

    it "joins lines with newlines and adds final newline" do
      result.add_line("line 1", decision: :kept_template, template_line: 1)
      result.add_line("line 2", decision: :kept_template, template_line: 2)
      result.add_line("line 3", decision: :kept_template, template_line: 3)

      expect(result.to_s).to eq("line 1\nline 2\nline 3\n")
    end

    it "preserves empty lines" do
      result.add_line("first", decision: :kept_template, template_line: 1)
      result.add_line("", decision: :kept_template, template_line: 2)
      result.add_line("third", decision: :kept_template, template_line: 3)

      expect(result.to_s).to eq("first\n\nthird\n")
    end
  end

  describe "#statistics" do
    let(:result) { described_class.new }

    it "returns empty hash for empty result" do
      expect(result.statistics).to eq({})
    end

    it "counts decisions by type" do
      result.add_line("line 1", decision: :kept_template, template_line: 1)
      result.add_line("line 2", decision: :kept_template, template_line: 2)
      result.add_line("line 3", decision: :kept_destination, dest_line: 3)
      result.add_line("line 4", decision: :appended, dest_line: 4)
      result.add_line("line 5", decision: :kept_template, template_line: 5)

      stats = result.statistics

      expect(stats[:kept_template]).to eq(3)
      expect(stats[:kept_destination]).to eq(1)
      expect(stats[:appended]).to eq(1)
    end

    it "counts all decision types" do
      result.add_line("line 1", decision: described_class::DECISION_KEPT_TEMPLATE, template_line: 1)
      result.add_line("line 2", decision: described_class::DECISION_KEPT_DEST, dest_line: 2)
      result.add_line("line 3", decision: described_class::DECISION_APPENDED, dest_line: 3)
      result.add_line("line 4", decision: described_class::DECISION_REPLACED, template_line: 4)
      result.add_line("line 5", decision: described_class::DECISION_FREEZE_BLOCK, dest_line: 5)

      stats = result.statistics

      expect(stats[described_class::DECISION_KEPT_TEMPLATE]).to eq(1)
      expect(stats[described_class::DECISION_KEPT_DEST]).to eq(1)
      expect(stats[described_class::DECISION_APPENDED]).to eq(1)
      expect(stats[described_class::DECISION_REPLACED]).to eq(1)
      expect(stats[described_class::DECISION_FREEZE_BLOCK]).to eq(1)
    end
  end

  describe "#lines_by_decision" do
    let(:result) { described_class.new }

    before do
      result.add_line("template line 1", decision: :kept_template, template_line: 1)
      result.add_line("dest line 1", decision: :kept_destination, dest_line: 5)
      result.add_line("template line 2", decision: :kept_template, template_line: 2)
      result.add_line("appended line", decision: :appended, dest_line: 10)
    end

    it "returns lines with matching decision" do
      template_lines = result.lines_by_decision(:kept_template)

      expect(template_lines.length).to eq(2)
      expect(template_lines[0][:result_line]).to eq(1)
      expect(template_lines[1][:result_line]).to eq(3)
    end

    it "returns empty array when no matches" do
      freeze_lines = result.lines_by_decision(:freeze_block)

      expect(freeze_lines).to be_empty
    end

    it "returns correct metadata for filtered lines" do
      dest_lines = result.lines_by_decision(:kept_destination)

      expect(dest_lines.length).to eq(1)
      expect(dest_lines[0][:dest_line]).to eq(5)
      expect(dest_lines[0][:decision]).to eq(:kept_destination)
    end
  end

  describe "#debug_output" do
    let(:result) { described_class.new }

    it "returns formatted debug information for empty result" do
      output = result.debug_output

      expect(output).to include("=== Merge Result Debug ===")
      expect(output).to include("Total lines: 0")
      expect(output).to include("Statistics: {}")
    end

    it "returns formatted debug information with line provenance" do
      result.add_line("# frozen_string_literal: true", decision: :kept_template, template_line: 1)
      result.add_line("VERSION = '1.0'", decision: :kept_destination, dest_line: 3)
      result.add_line("NEW_CONST = 'new'", decision: :appended, dest_line: 10)

      output = result.debug_output

      expect(output).to include("Total lines: 3")
      expect(output).to include("kept_template")
      expect(output).to include("kept_destination")
      expect(output).to include("appended")

      # Should show template line references
      expect(output).to include("T:1")

      # Should show destination line references
      expect(output).to include("D:3")
      expect(output).to include("D:10")

      # Should include actual line content
      expect(output).to include("frozen_string_literal")
      expect(output).to include("VERSION")
      expect(output).to include("NEW_CONST")
    end

    it "formats line numbers correctly" do
      result.add_line("line 1", decision: :kept_template, template_line: 1)
      result.add_line("line 2", decision: :kept_destination, dest_line: 2)

      output = result.debug_output

      # Line numbers should be right-aligned with consistent width
      expect(output).to match(/\s+1:/)
      expect(output).to match(/\s+2:/)
    end

    it "truncates long lines in debug output" do
      long_line = "a" * 100
      result.add_line(long_line, decision: :kept_template, template_line: 1)

      output = result.debug_output

      # Line should be truncated to ~60 chars
      expect(output).to include("a" * 60)
      expect(output).not_to include("a" * 100)
    end

    it "shows statistics summary" do
      result.add_line("line 1", decision: :kept_template, template_line: 1)
      result.add_line("line 2", decision: :kept_template, template_line: 2)
      result.add_line("line 3", decision: :kept_destination, dest_line: 3)

      output = result.debug_output

      expect(output).to match(/Statistics:.*kept_template.*2/)
      expect(output).to match(/Statistics:.*kept_destination.*1/)
    end
  end

  describe "decision constants" do
    it "defines all decision types" do
      expect(described_class::DECISION_KEPT_TEMPLATE).to eq(:kept_template)
      expect(described_class::DECISION_KEPT_DEST).to eq(:kept_destination)
      expect(described_class::DECISION_APPENDED).to eq(:appended)
      expect(described_class::DECISION_REPLACED).to eq(:replaced)
      expect(described_class::DECISION_FREEZE_BLOCK).to eq(:freeze_block)
    end
  end

  describe "integration scenarios" do
    let(:result) { described_class.new }

    it "handles complex merge scenario" do
      # Simulate a real merge result
      result.add_line("# frozen_string_literal: true", decision: :kept_template, template_line: 1)
      result.add_line("", decision: :kept_template, template_line: 2)
      result.add_line("VERSION = '2.0.0'", decision: :replaced, template_line: 3, dest_line: 3, comment: "Updated from template")
      result.add_line("", decision: :kept_template, template_line: 4)
      result.add_line("# kettle-dev:freeze", decision: :freeze_block, dest_line: 5)
      result.add_line("CUSTOM = 'preserved'", decision: :freeze_block, dest_line: 6)
      result.add_line("# kettle-dev:unfreeze", decision: :freeze_block, dest_line: 7)
      result.add_line("", decision: :kept_template, template_line: 5)
      result.add_line("def hello", decision: :kept_destination, dest_line: 10)
      result.add_line("  puts 'world'", decision: :kept_destination, dest_line: 11)
      result.add_line("end", decision: :kept_destination, dest_line: 12)
      result.add_line("", decision: :kept_destination, dest_line: 13)
      result.add_line("def custom", decision: :appended, dest_line: 15)
      result.add_line("  'custom method'", decision: :appended, dest_line: 16)
      result.add_line("end", decision: :appended, dest_line: 17)

      # Verify final output
      output = result.to_s
      expect(output).to include("frozen_string_literal")
      expect(output).to include("VERSION = '2.0.0'")
      expect(output).to include("CUSTOM = 'preserved'")
      expect(output).to include("def hello")
      expect(output).to include("def custom")

      # Verify statistics
      stats = result.statistics
      expect(stats[:kept_template]).to eq(4)
      expect(stats[:replaced]).to eq(1)
      expect(stats[:freeze_block]).to eq(3)
      expect(stats[:kept_destination]).to eq(4)
      expect(stats[:appended]).to eq(3)

      # Verify debug output includes all decision types
      debug = result.debug_output
      expect(debug).to include("kept_template")
      expect(debug).to include("replaced")
      expect(debug).to include("freeze_block")
      expect(debug).to include("kept_destination")
      expect(debug).to include("appended")
    end
  end
end
