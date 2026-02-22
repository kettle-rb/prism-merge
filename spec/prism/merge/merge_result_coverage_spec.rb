# frozen_string_literal: true

RSpec.describe Prism::Merge::MergeResult do
  describe "#add_node with leading comments that have blank lines between them" do
    let(:result) { described_class.new }

    context "template source with blank lines between leading comments" do
      it "preserves blank lines between non-contiguous leading comments" do
        content = <<~RUBY
          # First comment

          # Second comment
          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: analysis)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# First comment")
        expect(result_text).to include("# Second comment")
        expect(result_text).to include("def example")
      end
    end

    context "destination source with blank lines between leading comments" do
      it "preserves blank lines between non-contiguous leading comments" do
        content = <<~RUBY
          # First comment

          # Second comment
          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: analysis)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# First comment")
        expect(result_text).to include("# Second comment")

        # Verify metadata uses dest_line, not template_line
        result.line_metadata.each do |meta|
          expect(meta[:decision]).to eq(:kept_destination)
          expect(meta[:template_line]).to be_nil
        end
      end
    end

    context "with blank line between last leading comment and node" do
      it "preserves gap between last comment and node (template)" do
        content = <<~RUBY
          # A comment

          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: analysis)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# A comment")
        expect(result_text).to include("def example")
      end

      it "preserves gap between last comment and node (destination)" do
        content = <<~RUBY
          # A comment

          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: analysis)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# A comment")
        expect(result_text).to include("def example")

        result.line_metadata.each do |meta|
          expect(meta[:template_line]).to be_nil
        end
      end
    end

    context "without source_analysis" do
      it "adds blank lines between non-contiguous leading comments using empty string fallback" do
        content = <<~RUBY
          # First comment

          # Second comment
          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: nil)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# First comment")
        expect(result_text).to include("# Second comment")
      end

      it "adds blank lines gap for destination source without analysis" do
        content = <<~RUBY
          # First comment

          # Second comment
          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: nil)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# First comment")
        expect(result_text).to include("# Second comment")

        result.line_metadata.each do |meta|
          expect(meta[:template_line]).to be_nil
        end
      end

      it "adds blank lines between last comment and node for template without analysis" do
        content = <<~RUBY
          # A comment

          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_template, source: :template, source_analysis: nil)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# A comment")
        expect(result_text).to include("def example")
      end

      it "adds blank lines between last comment and node for dest without analysis" do
        content = <<~RUBY
          # A comment

          def example
            "hello"
          end
        RUBY
        analysis = Prism::Merge::FileAnalysis.new(content)
        node_info = analysis.nodes_with_comments.first

        result.add_node(node_info, decision: :kept_destination, source: :destination, source_analysis: nil)

        result_text = result.lines.join("\n")
        expect(result_text).to include("# A comment")
        expect(result_text).to include("def example")

        result.line_metadata.each do |meta|
          expect(meta[:template_line]).to be_nil
        end
      end
    end
  end
end
