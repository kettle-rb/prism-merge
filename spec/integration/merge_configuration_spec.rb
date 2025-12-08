# frozen_string_literal: true

require "spec_helper"

# Tests for SmartMerger configuration options
RSpec.describe "Merge Configuration Options" do
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

  describe "with add_template_only_nodes: false, preference: :template" do
    it "uses template for matches, skips template-only" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: false,
        preference: :template,
      )
      result = merger.merge

      expect(result).to include("DEST_ONLY")
      expect(result).not_to include("TEMPLATE_ONLY")
      expect(result).to include("def shared_method")
    end
  end

  describe "with add_template_only_nodes: true, preference: :template" do
    it "uses template for matches, includes template-only" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
        preference: :template,
      )
      result = merger.merge

      expect(result).to include("DEST_ONLY")
      expect(result).to include("TEMPLATE_ONLY")
    end
  end

  describe "with add_template_only_nodes: false, preference: :destination" do
    it "uses destination for matches, skips template-only" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: false,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("DEST_ONLY")
      expect(result).not_to include("TEMPLATE_ONLY")
    end
  end

  describe "with add_template_only_nodes: true, preference: :destination" do
    it "uses destination for matches, includes template-only" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("DEST_ONLY")
      expect(result).to include("TEMPLATE_ONLY")
    end
  end

  describe "complex combination of features" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN = "template"
        # kettle-dev:unfreeze

        TEMPLATE_ONLY = "new"

        def shared_method
          "template"
        end

        def template_only_method
          "template"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN = "dest"
        EXTRA_FROZEN = "dest"
        # kettle-dev:unfreeze

        def shared_method
          "dest"
        end

        def dest_only_method
          "dest"
        end
      RUBY
    end

    it "handles complex combination of features" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
        preference: :destination,
        freeze_token: "kettle-dev",
      )
      result = merger.merge

      # Freeze block should use dest
      expect(result).to include('FROZEN = "dest"')
      expect(result).to include('EXTRA_FROZEN = "dest"')

      # Template-only should be added
      expect(result).to include("TEMPLATE_ONLY")
      expect(result).to include("template_only_method")

      # Destination-only should be kept
      expect(result).to include("dest_only_method")

      # Shared method should use destination preference
      expect(result).to include("shared_method")
    end
  end
end
