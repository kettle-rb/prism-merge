# frozen_string_literal: true

require "spec_helper"

# Tests for MergeResult decision types and rendering
RSpec.describe "MergeResult Decision Types" do
  describe "DECISION_FREEZE_BLOCK tracking" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN = "template"
        # kettle-dev:unfreeze

        def method
          "method"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN = "dest"
        EXTRA = "dest"
        # kettle-dev:unfreeze

        def method
          "method"
        end
      RUBY
    end

    it "tracks freeze block decisions" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include('FROZEN = "dest"')
      expect(result).to include('EXTRA = "dest"')
      expect(result).to include("kettle-dev:freeze")
    end
  end

  describe "DECISION_REPLACED tracking" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg)
          "template"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method(arg)
          "dest"
        end
      RUBY
    end

    it "tracks replaced decisions with template preference" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :template,
      )
      result = merger.merge

      expect(result).to include('"template"')
      expect(result).not_to include('"dest"')
    end

    it "tracks replaced decisions with destination preference" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include('"dest"')
      expect(result).not_to include('"template"')
    end
  end

  describe "DECISION_KEPT_TEMPLATE tracking" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        TEMPLATE_ONLY = "value"

        def shared_method
          "shared"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def shared_method
          "shared"
        end
      RUBY
    end

    it "tracks template-only kept decisions" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to include("TEMPLATE_ONLY")
      expect(result).to include("shared_method")
    end
  end

  describe "DECISION_KEPT_DEST tracking" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def shared_method
          "shared"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        DEST_ONLY = "value"

        def shared_method
          "shared"
        end
      RUBY
    end

    it "tracks destination-only kept decisions" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("DEST_ONLY")
      expect(result).to include("shared_method")
    end
  end

  describe "DECISION_APPENDED tracking" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Template orphan comment

        def method
          "method"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Dest unique orphan comment
        # Another unique line

        def method
          "method"
        end
      RUBY
    end

    it "tracks appended decisions for unique content" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("method")
      expect(result).to include("comment")
    end
  end

  describe "with conflict markers disabled" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        CONST = "template"
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        CONST = "dest"
      RUBY
    end

    it "produces merged output without conflict markers" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).not_to include("<<<<<<<")
      expect(result).not_to include(">>>>>>>")
      expect(result).not_to include("=======")
    end
  end
end
