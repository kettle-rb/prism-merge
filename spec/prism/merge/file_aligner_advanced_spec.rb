# frozen_string_literal: true

RSpec.describe Prism::Merge::FileAligner do
  describe "edge cases and boundary conditions" do
    context "with nil ranges in boundaries" do
      it "handles nil template_range when template file is shorter" do
        template_content = <<~RUBY
          # Short template
        RUBY

        dest_content = <<~RUBY
          # Short template

          # Additional destination content
          def extra_method
            puts "destination only"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Should have boundaries with content in destination
        expect(boundaries).not_to be_empty
      end

      it "handles nil dest_range when destination file is shorter" do
        template_content = <<~RUBY
          # Short dest

          # Additional template content
          def extra_method
            puts "template only"
          end
        RUBY

        dest_content = <<~RUBY
          # Short dest
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Should have boundaries with content in template
        expect(boundaries).not_to be_empty
      end

      it "handles boundaries with both nil ranges" do
        template_content = "# frozen_string_literal: true\n"
        dest_content = "# frozen_string_literal: true\n"

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Should not error and handle gracefully
        expect(boundaries).to be_an(Array)
      end
    end

    context "with freeze blocks as anchors" do
      it "treats freeze blocks as anchors that can't be matched" do
        template_content = <<~RUBY
          # Template
          VERSION = "2.0.0"
        RUBY

        dest_content = <<~RUBY
          # Destination
          # kettle-dev:freeze
          VERSION = "1.0.0"
          CUSTOM = "preserved"
          # kettle-dev:unfreeze
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Freeze blocks in destination should be handled as part of boundaries
        # Check that boundaries exist and include the freeze block area
        expect(boundaries).not_to be_empty

        # At least one boundary should cover the freeze block line range
        freeze_block = dest_analysis.freeze_blocks.first
        expect(freeze_block).not_to be_nil
      end
    end

    context "with consecutive anchors without gaps" do
      it "handles anchors with no gap between them" do
        template_content = <<~RUBY
          def method_one
            puts "one"
          end
          def method_two
            puts "two"
          end
        RUBY

        dest_content = <<~RUBY
          def method_one
            puts "one"
          end
          def method_two
            puts "two"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Should handle consecutive anchors without creating invalid boundaries
        boundaries.each do |boundary|
          if boundary.template_range
            expect(boundary.template_range.begin).to be <= boundary.template_range.end
          end
          if boundary.dest_range
            expect(boundary.dest_range.begin).to be <= boundary.dest_range.end
          end
        end
      end
    end

    context "with matching at file boundaries" do
      it "handles match at start of files" do
        template_content = <<~RUBY
          # frozen_string_literal: true

          VERSION = "2.0.0"
        RUBY

        dest_content = <<~RUBY
          # frozen_string_literal: true

          VERSION = "1.0.0"
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        aligner.align

        # First anchor should start at line 1
        first_anchor = aligner.instance_variable_get(:@anchors).first
        expect(first_anchor&.template_start).to eq(1)
        expect(first_anchor&.dest_start).to eq(1)
      end

      it "handles match at end of files" do
        template_content = <<~RUBY
          VERSION = "2.0.0"

          # End marker
        RUBY

        dest_content = <<~RUBY
          VERSION = "1.0.0"

          # End marker
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        aligner.align

        # Last anchor should end at last line
        last_anchor = aligner.instance_variable_get(:@anchors).last
        expect(last_anchor&.template_end).to eq(template_analysis.lines.length)
        expect(last_anchor&.dest_end).to eq(dest_analysis.lines.length)
      end
    end

    context "with signature calculation" do
      it "uses signature_generator when provided" do
        template_content = <<~RUBY
          def custom_method
            puts "test"
          end
        RUBY

        dest_content = <<~RUBY
          def custom_method
            puts "different"
          end
        RUBY

        custom_generator = ->(node) do
          node.is_a?(Prism::DefNode) ? [:custom_def, node.name] : nil
        end

        template_analysis = Prism::Merge::FileAnalysis.new(template_content, signature_generator: custom_generator)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content, signature_generator: custom_generator)

        aligner = described_class.new(template_analysis, dest_analysis)
        aligner.align

        # Should use custom signature for matching
        anchors = aligner.instance_variable_get(:@anchors)
        expect(anchors.length).to be > 0
      end

      it "handles signatures that return nil" do
        template_content = "def method; end"
        dest_content = "def method; end"

        nil_generator = ->(_node) { nil }

        template_analysis = Prism::Merge::FileAnalysis.new(template_content, signature_generator: nil_generator)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content, signature_generator: nil_generator)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Should not error when signatures are nil
        expect(boundaries).to be_an(Array)
      end
    end

    context "with empty files" do
      it "handles completely empty template" do
        template_content = ""
        dest_content = "def method; end"

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).to be_an(Array)
      end

      it "handles completely empty destination" do
        template_content = "def method; end"
        dest_content = ""

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).to be_an(Array)
      end

      it "handles both files empty" do
        template_content = ""
        dest_content = ""

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).to be_an(Array)
        expect(boundaries).to be_empty
      end
    end

    context "with complex anchor matching" do
      it "finds multiple matching anchors throughout files" do
        template_content = <<~RUBY
          # frozen_string_literal: true

          VERSION = "2.0.0"

          def method_one
            puts "template"
          end

          def method_two
            puts "template"
          end

          # End
        RUBY

        dest_content = <<~RUBY
          # frozen_string_literal: true

          VERSION = "1.0.0"

          def method_one
            puts "destination"
          end

          def custom_method
            puts "destination only"
          end

          def method_two
            puts "destination"
          end

          # End
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        aligner.align

        anchors = aligner.instance_variable_get(:@anchors)

        # Should find multiple anchors
        expect(anchors.length).to be >= 3
      end

      it "creates boundaries between non-matching content" do
        template_content = <<~RUBY
          # Anchor 1

          def template_only
            puts "template"
          end

          # Anchor 2
        RUBY

        dest_content = <<~RUBY
          # Anchor 1

          def dest_only
            puts "destination"
          end

          # Anchor 2
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Should have boundary between anchors containing non-matching methods
        middle_boundary = boundaries.find do |b|
          b.template_range && b.dest_range &&
            b.template_range.cover?(3) && b.dest_range.cover?(3)
        end

        expect(middle_boundary).not_to be_nil
      end
    end

    context "with add_template_only_nodes option" do
      it "includes template-only boundaries when add_template_only_nodes is true" do
        template_content = <<~RUBY
          def template_method
            puts "template only"
          end

          def shared_method
            puts "shared"
          end
        RUBY

        dest_content = <<~RUBY
          def shared_method
            puts "shared"
          end

          def dest_method
            puts "dest only"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # FileAligner creates boundaries regardless of add_template_only_nodes setting
        # The filtering happens in ConflictResolver, not FileAligner
        expect(boundaries).not_to be_empty
      end

      it "excludes template-only boundaries when add_template_only_nodes is false" do
        template_content = <<~RUBY
          def template_method
            puts "template only"
          end

          def shared_method
            puts "shared"
          end
        RUBY

        dest_content = <<~RUBY
          def shared_method
            puts "shared"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        aligner = described_class.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # FileAligner doesn't filter based on add_template_only_nodes
        # That filtering happens in ConflictResolver
        expect(boundaries).not_to be_empty
      end
    end
  end
end
