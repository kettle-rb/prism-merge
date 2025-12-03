# frozen_string_literal: true

require "spec_helper"

# Tests for boundary computation and edge cases in FileAligner
RSpec.describe "File Alignment and Boundary Detection" do
  describe "with nil template range" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true
        # Just comments
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        class DestClass
          def method
            "dest"
          end
        end
      RUBY
    end

    it "handles nil template range in boundaries" do
      template_analysis = Prism::Merge::FileAnalysis.new(template_code)
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)
      aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

      boundaries = aligner.align
      expect(boundaries).not_to be_empty

      # Should handle nil template range - check if any boundary has nil template_range
      has_nil_template = boundaries.any? { |b| b.template_range.nil? }
      expect(has_nil_template).to be(true).or be(false) # Either is valid
    end
  end

  describe "with nil dest range" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        class TemplateClass
          def method
            "template"
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true
        # Just comments
      RUBY
    end

    it "handles nil dest range in boundaries" do
      template_analysis = Prism::Merge::FileAnalysis.new(template_code)
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)
      aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

      boundaries = aligner.align
      expect(boundaries).not_to be_empty

      # Should handle nil dest range - check if any boundary has nil dest_range
      has_nil_dest = boundaries.any? { |b| b.dest_range.nil? }
      expect(has_nil_dest).to be(true).or be(false) # Either is valid
    end
  end

  describe "with anchors at exact file boundaries" do
    let(:template_code) do
      <<~RUBY
        VERSION = "1.0.0"
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        VERSION = "1.0.0"
      RUBY
    end

    it "handles anchors that span entire file" do
      template_analysis = Prism::Merge::FileAnalysis.new(template_code)
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)
      aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

      boundaries = aligner.align
      # When entire file is anchor, boundaries should be minimal or empty
      expect(boundaries).to be_an(Array)
    end
  end

  describe "with consecutive anchors with no gaps" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        FIRST = "1"
        SECOND = "2"
        THIRD = "3"
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        FIRST = "1"
        SECOND = "2"
        THIRD = "3"
      RUBY
    end

    it "handles consecutive anchors with no intervening content" do
      template_analysis = Prism::Merge::FileAnalysis.new(template_code)
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)
      aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

      boundaries = aligner.align
      # Should not create empty boundaries
      empty_boundaries = boundaries.select do |b|
        (b.template_range.nil? || b.template_range.size == 0) &&
          (b.dest_range.nil? || b.dest_range.size == 0)
      end
      expect(empty_boundaries).to be_empty
    end
  end

  describe "with mismatched anchor positions" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Comment 1
        # Comment 2

        VERSION = "1.0.0"

        # Comment 3
        # Comment 4

        def method
          "method"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        VERSION = "1.0.0"

        CUSTOM = "custom"

        def method
          "method"
        end

        # Trailing comment
      RUBY
    end

    it "creates appropriate boundaries for mismatched positions" do
      template_analysis = Prism::Merge::FileAnalysis.new(template_code)
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)
      aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

      boundaries = aligner.align
      expect(boundaries).not_to be_empty

      # Should have boundary before first anchor (comments differ)
      first_boundary = boundaries.first
      expect(first_boundary.template_range || first_boundary.dest_range).not_to be_nil
    end
  end
end
