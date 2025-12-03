# frozen_string_literal: true

require "spec_helper"

# Tests for signature matching with various parameter types
RSpec.describe "Signature Matching" do
  describe "with default parameter changes" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg, default: "new_default")
          arg
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg, default: "old_default")
          arg + " custom"
        end
      RUBY
    end

    it "treats methods with different defaults as signature match" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      # Should keep destination version due to preference
      expect(result).to include("old_default")
      expect(result).to include("custom")
    end
  end

  describe "with keyword rest parameter differences" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg, **kwargs)
          [arg, kwargs]
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg, **options)
          [arg, options, "custom"]
        end
      RUBY
    end

    it "treats methods with different kwrest names as signature match" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      # Should use destination version due to preference
      expect(result).to include("def method")
      expect(result).to include("options")
      expect(result).to include("custom")
    end
  end

  describe "with block parameter changes" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg, &block)
          block.call(arg)
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg, &proc)
          proc.call(arg) + " custom"
        end
      RUBY
    end

    it "treats methods with different block param names as signature match" do
      template_analysis = Prism::Merge::FileAnalysis.new(template_code)
      dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

      # Both should be analyzed successfully
      expect(template_analysis.statements.size).to eq(1)
      expect(dest_analysis.statements.size).to eq(1)

      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      # Should merge successfully
      expect(result).to include("method")
    end
  end
end
