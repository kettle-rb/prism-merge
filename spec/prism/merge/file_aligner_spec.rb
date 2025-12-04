# frozen_string_literal: true

RSpec.describe Prism::Merge::FileAligner do
  let(:template_analysis) { Prism::Merge::FileAnalysis.new(template_content) }
  let(:dest_analysis) { Prism::Merge::FileAnalysis.new(dest_content) }
  let(:aligner) { described_class.new(template_analysis, dest_analysis) }

  describe "#align" do
    context "with identical files" do
      let(:template_content) do
        <<~RUBY
          def hello
            puts "world"
          end
        RUBY
      end
      let(:dest_content) { template_content }

      it "finds complete match as single anchor" do
        boundaries = aligner.align

        expect(aligner.anchors.length).to be >= 1
        expect(boundaries).to be_empty # No differences, no boundaries
      end
    end

    context "with completely different files" do
      let(:template_content) do
        <<~RUBY
          def template_method
            1
          end
        RUBY
      end
      let(:dest_content) do
        <<~RUBY
          def dest_method
            2
          end
        RUBY
      end

      it "creates single boundary covering all lines" do
        boundaries = aligner.align

        expect(aligner.anchors).to be_empty
        expect(boundaries.length).to eq(1)
        expect(boundaries.first.template_range).to eq(1..3)
        expect(boundaries.first.dest_range).to eq(1..3)
      end
    end

    context "with partial matches" do
      let(:template_content) do
        <<~RUBY
          # frozen_string_literal: true

          def common_method
            puts "same"
          end

          def template_only
            1
          end
        RUBY
      end
      let(:dest_content) do
        <<~RUBY
          # frozen_string_literal: true

          def common_method
            puts "same"
          end

          def dest_only
            2
          end
        RUBY
      end

      it "identifies common sections as anchors and differences as boundaries" do
        boundaries = aligner.align

        # Should have at least one anchor for the common method
        expect(aligner.anchors.length).to be >= 1

        # Should have boundary for the different methods
        expect(boundaries).not_to be_empty
      end
    end

    context "with freeze blocks" do
      # Use kettle-dev as freeze token to match the markers in test data
      let(:template_analysis) { Prism::Merge::FileAnalysis.new(template_content, freeze_token: "kettle-dev") }
      let(:dest_analysis) { Prism::Merge::FileAnalysis.new(dest_content, freeze_token: "kettle-dev") }

      let(:template_content) do
        <<~RUBY
          gem "rails"

          # kettle-dev:freeze
          # Placeholder
          # kettle-dev:unfreeze
        RUBY
      end
      let(:dest_content) do
        <<~RUBY
          gem "rails"

          # kettle-dev:freeze
          gem "custom"
          # kettle-dev:unfreeze
        RUBY
      end

      it "identifies freeze blocks as high-priority anchors" do
        aligner.align

        freeze_anchors = aligner.anchors.select { |a| a.match_type == :freeze_block }
        expect(freeze_anchors).not_to be_empty
        expect(freeze_anchors.first.score).to eq(100)
      end
    end

    context "with mixed content" do
      let(:template_content) do
        <<~RUBY
          # frozen_string_literal: true

          VERSION = "2.0.0"

          def hello
            puts "world"
          end
        RUBY
      end
      let(:dest_content) do
        <<~RUBY
          # frozen_string_literal: true

          VERSION = "1.0.0"

          def hello
            puts "world"
          end

          def extra
            42
          end
        RUBY
      end

      it "creates boundaries for differences and anchors for matches" do
        aligner.align

        # Should have anchor for VERSION (with magic comment as leading comment)
        # Magic comments are attached to the first statement by Prism
        version_anchor = aligner.anchors.find do |a|
          # Check if any line in the anchor range contains VERSION
          (a.template_start..a.template_end).any? do |line_num|
            template_analysis.line_at(line_num)&.include?("VERSION")
          end
        end
        expect(version_anchor).not_to be_nil
        expect(version_anchor.match_type).to eq(:signature_match)
        # The anchor should include the magic comment (line 1) and VERSION (line 3)
        expect(version_anchor.template_start).to eq(1) # magic comment attached as leading comment
        expect(version_anchor.template_end).to eq(3)   # VERSION constant

        # Should have anchor for hello method
        hello_anchor = aligner.anchors.find do |a|
          template_analysis.line_at(a.template_start)&.include?("def hello")
        end
        expect(hello_anchor).not_to be_nil
      end
    end
  end

  describe "Anchor" do
    it "provides convenience methods" do
      anchor = described_class::Anchor.new(1, 5, 2, 6, :exact_match, 5)

      expect(anchor.template_range).to eq(1..5)
      expect(anchor.dest_range).to eq(2..6)
      expect(anchor.length).to eq(5)
    end
  end

  describe "Boundary" do
    it "provides convenience methods" do
      boundary = described_class::Boundary.new(6..10, 7..12, nil, nil)

      expect(boundary.template_lines).to eq([6, 7, 8, 9, 10])
      expect(boundary.dest_lines).to eq([7, 8, 9, 10, 11, 12])
    end
  end
end
