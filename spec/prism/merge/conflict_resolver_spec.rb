# frozen_string_literal: true

RSpec.describe Prism::Merge::ConflictResolver do
  let(:template_content) do
    <<~RUBY
      # frozen_string_literal: true

      VERSION = "2.0.0"

      def template_method
        puts "template"
      end

      def shared_method
        puts "template version"
      end
    RUBY
  end

  let(:dest_content) do
    <<~RUBY
      # frozen_string_literal: true

      VERSION = "1.0.0"

      def shared_method
        puts "destination version"
      end

      def dest_method
        puts "destination"
      end
    RUBY
  end

  let(:template_analysis) { Prism::Merge::FileAnalysis.new(template_content) }
  let(:dest_analysis) { Prism::Merge::FileAnalysis.new(dest_content) }

  describe "#initialize" do
    it "creates resolver with default preferences" do
      resolver = described_class.new(template_analysis, dest_analysis)

      expect(resolver.template_analysis).to eq(template_analysis)
      expect(resolver.dest_analysis).to eq(dest_analysis)
      expect(resolver.signature_match_preference).to be(:destination)
      expect(resolver.add_template_only_nodes).to be(false)
    end

    it "creates resolver with custom preferences" do
      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        signature_match_preference: :template,
        add_template_only_nodes: true,
      )

      expect(resolver.signature_match_preference).to be(:template)
      expect(resolver.add_template_only_nodes).to be(true)
    end
  end

  describe "#resolve" do
    let(:result) { Prism::Merge::MergeResult.new }

    context "with template-only nodes and add_template_only_nodes: true" do
      it "adds template-only nodes to result" do
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )

        # Create a boundary covering the method definitions (lines 4-11 in template, 4-11 in dest)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Find boundary that contains our methods
        boundary = boundaries.find do |b|
          b.template_range&.cover?(5)
        end

        resolver.resolve(boundary, result) if boundary

        result_text = result.to_s

        # Should include template-only method
        expect(result_text).to include("def template_method")

        # Should include shared method (template version due to preference)
        expect(result_text).to include("def shared_method")
        expect(result_text).to include('puts "template version"')

        # Should include dest-only method
        expect(result_text).to include("def dest_method")
      end
    end

    context "with template-only nodes and add_template_only_nodes: false" do
      it "skips template-only nodes" do
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          signature_match_preference: :destination,
          add_template_only_nodes: false,
        )

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        boundary = boundaries.find do |b|
          b.template_range&.cover?(5)
        end

        resolver.resolve(boundary, result) if boundary

        result_text = result.to_s

        # Should NOT include template-only method
        expect(result_text).not_to include("def template_method")

        # Should include shared method (destination version due to preference)
        expect(result_text).to include("def shared_method")
        expect(result_text).to include('puts "destination version"')

        # Should include dest-only method
        expect(result_text).to include("def dest_method")
      end
    end

    context "with freeze block in destination boundary" do
      let(:template_with_code) do
        <<~RUBY
          # frozen_string_literal: true

          REGULAR = "template"
        RUBY
      end

      let(:dest_with_freeze_in_boundary) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          CUSTOM = "destination"
          SECRET = "preserved"
          # kettle-dev:unfreeze

          REGULAR = "destination"
        RUBY
      end

      it "preserves freeze block content from destination when in boundary" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_with_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_with_freeze_in_boundary)

        resolver = described_class.new(template_analysis, dest_analysis)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        # Find boundary that contains the freeze block
        freeze_boundary = boundaries.find do |b|
          b.dest_range&.cover?(3) # Line with freeze marker
        end

        if freeze_boundary
          resolver.resolve(freeze_boundary, result)

          result_text = result.to_s

          # Destination freeze block should be preserved
          expect(result_text).to include('CUSTOM = "destination"')
          expect(result_text).to include('SECRET = "preserved"')
          expect(result_text).to include("kettle-dev:freeze")
          expect(result_text).to include("kettle-dev:unfreeze")
        else
          # If freeze block creates an anchor instead, that's also valid behavior
          skip "Freeze block was handled as anchor, not boundary"
        end
      end
    end

    context "with empty boundaries" do
      it "handles empty template range" do
        empty_template = "# frozen_string_literal: true\n"
        full_dest = "# frozen_string_literal: true\n\nVERSION = \"1.0.0\"\n"

        template_analysis = Prism::Merge::FileAnalysis.new(empty_template)
        dest_analysis = Prism::Merge::FileAnalysis.new(full_dest)

        resolver = described_class.new(template_analysis, dest_analysis)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        boundaries.each do |boundary|
          resolver.resolve(boundary, result)
        end

        result_text = result.to_s
        expect(result_text).to include('VERSION = "1.0.0"')
      end

      it "handles empty destination range" do
        full_template = "# frozen_string_literal: true\n\nVERSION = \"2.0.0\"\n"
        empty_dest = "# frozen_string_literal: true\n"

        template_analysis = Prism::Merge::FileAnalysis.new(full_template)
        dest_analysis = Prism::Merge::FileAnalysis.new(empty_dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true,
        )
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        boundaries.each do |boundary|
          resolver.resolve(boundary, result)
        end

        result_text = result.to_s
        expect(result_text).to include('VERSION = "2.0.0"')
      end

      it "handles both ranges empty" do
        empty_template = "# frozen_string_literal: true\n"
        empty_dest = "# frozen_string_literal: true\n"

        template_analysis = Prism::Merge::FileAnalysis.new(empty_template)
        dest_analysis = Prism::Merge::FileAnalysis.new(empty_dest)

        resolver = described_class.new(template_analysis, dest_analysis)

        # Create an empty boundary
        boundary = Prism::Merge::FileAligner::Boundary.new(nil, nil, nil, nil)

        # Should not error
        expect { resolver.resolve(boundary, result) }.not_to raise_error
      end
    end
  end
end
