# frozen_string_literal: true

require "spec_helper"

# Error handling and edge case tests
RSpec.describe "Error Handling and Edge Cases" do
  describe "FileAnalysis with parse errors" do
    context "with syntax errors in template" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          def broken_method(
            # Missing closing paren
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          def working_method
            "works"
          end
        RUBY
      end

      it "handles template parse errors gracefully" do
        expect {
          Prism::Merge::FileAnalysis.new(template_code)
        }.not_to raise_error
      end

      it "raises TemplateParseError when trying to merge with template parse errors" do
        expect {
          merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
          merger.merge
        }.to raise_error(Prism::Merge::TemplateParseError)
      end
    end

    context "with syntax errors in destination" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          def working_method
            "works"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          def broken_method(
            # Missing closing paren
          end
        RUBY
      end

      it "handles destination parse errors gracefully" do
        expect {
          Prism::Merge::FileAnalysis.new(dest_code)
        }.not_to raise_error
      end

      it "raises DestinationParseError when trying to merge with destination parse errors" do
        expect {
          merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
          merger.merge
        }.to raise_error(Prism::Merge::DestinationParseError)
      end
    end
  end

  describe "FileAligner boundary edge cases" do
    context "with nil ranges in boundaries" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          # Only comments
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          class DestClass
          end
        RUBY
      end

      it "handles boundaries with nil template range" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).not_to be_empty
        expect(boundaries).to all(be_a(Prism::Merge::FileAligner::Boundary))
      end
    end

    context "with completely empty files" do
      let(:template_code) { "" }
      let(:dest_code) { "" }

      it "handles both empty files" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).to be_an(Array)
      end
    end

    context "with only whitespace" do
      let(:template_code) { "   \n\n  \n  " }
      let(:dest_code) { "  \n  \n  " }

      it "handles whitespace-only files" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).to be_an(Array)
      end
    end
  end

  describe "ConflictResolver with edge cases" do
    context "with very long method bodies" do
      let(:template_code) do
        code = +"# frozen_string_literal: true\n\ndef long_method\n"
        100.times { |i| code << "  line_#{i} = #{i}\n" }
        code << "end\n"
        code
      end

      let(:dest_code) do
        code = +"# frozen_string_literal: true\n\ndef long_method\n"
        150.times { |i| code << "  line_#{i} = #{i}\n" }
        code << "end\n"
        code
      end

      it "handles very long method bodies" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
        )
        result = merger.merge

        expect(result).to include("long_method")
        expect(result).to include("line_149")
      end
    end

    context "with many similar methods" do
      let(:template_code) do
        code = +"# frozen_string_literal: true\n\n"
        50.times do |i|
          code << "def method_#{i}\n  'template_#{i}'\nend\n\n"
        end
        code
      end

      let(:dest_code) do
        code = +"# frozen_string_literal: true\n\n"
        50.times do |i|
          code << "def method_#{i}\n  'dest_#{i}'\nend\n\n"
        end
        code
      end

      it "handles many similar method signatures" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
        )
        result = merger.merge

        expect(result).to include("method_0")
        expect(result).to include("method_49")
        expect(result).to include("dest_25")
      end
    end

    context "with deeply nested blocks" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          def deep_method
            1.times do
              2.times do
                3.times do
                  4.times do
                    5.times do
                      "deep"
                    end
                  end
                end
              end
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          def deep_method
            1.times do
              2.times do
                3.times do
                  4.times do
                    5.times do
                      "deep_custom"
                    end
                  end
                end
              end
            end
          end
        RUBY
      end

      it "handles deeply nested block structures" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include("deep_method")
      end
    end
  end

  describe "SmartMerger configuration combinations" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        TEMPLATE_ONLY = "template"

        def shared_method
          "template"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        DEST_ONLY = "dest"

        def shared_method
          "dest"
        end
      RUBY
    end

    context "with add_template_only_nodes: false, signature_match_preference: :template" do
      it "uses template for matches, skips template-only" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: false,
          signature_match_preference: :template,
        )
        result = merger.merge

        expect(result).to include("DEST_ONLY")
        expect(result).not_to include("TEMPLATE_ONLY")
        expect(result).to include("def shared_method")
      end
    end

    context "with add_template_only_nodes: true, signature_match_preference: :template" do
      it "uses template for matches, includes template-only" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: true,
          signature_match_preference: :template,
        )
        result = merger.merge

        expect(result).to include("DEST_ONLY")
        expect(result).to include("TEMPLATE_ONLY")
      end
    end

    context "with add_template_only_nodes: false, signature_match_preference: :destination" do
      it "uses destination for matches, skips template-only" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: false,
          signature_match_preference: :destination,
        )
        result = merger.merge

        expect(result).to include("DEST_ONLY")
        expect(result).not_to include("TEMPLATE_ONLY")
      end
    end

    context "with add_template_only_nodes: true, signature_match_preference: :destination" do
      it "uses destination for matches, includes template-only" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: true,
          signature_match_preference: :destination,
        )
        result = merger.merge

        expect(result).to include("DEST_ONLY")
        expect(result).to include("TEMPLATE_ONLY")
      end
    end
  end

  describe "MergeResult line tracking" do
    context "with complex merge decisions" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # Template comment
          def method_a
            "template"
          end

          # Another comment
          def method_b
            "template"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # Dest comment
          def method_a
            "dest"
          end

          def custom_method
            "custom"
          end

          # Different comment
          def method_b
            "dest"
          end
        RUBY
      end

      it "tracks line origins correctly" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
        )
        result = merger.merge

        expect(result).to include("method_a")
        expect(result).to include("method_b")
        expect(result).to include("custom_method")
      end
    end
  end

  describe "Performance with large files" do
    context "with 100+ nodes" do
      let(:template_code) do
        code = +"# frozen_string_literal: true\n\n"
        100.times do |i|
          code << "CONST_#{i} = #{i}\n"
        end
        code
      end

      let(:dest_code) do
        code = +"# frozen_string_literal: true\n\n"
        100.times do |i|
          code << "CONST_#{i} = #{i * 2}\n"
        end
        code << "CUSTOM = 'custom'\n"
        code
      end

      it "handles large files efficiently" do
        start_time = Time.now

        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
        )
        result = merger.merge

        elapsed = Time.now - start_time

        expect(result).to include("CONST_0")
        expect(result).to include("CONST_99")
        expect(result).to include("CUSTOM")
        expect(elapsed).to be < 5.0 # Should complete in under 5 seconds
      end
    end
  end
end
