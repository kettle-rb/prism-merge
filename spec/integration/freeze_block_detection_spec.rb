# frozen_string_literal: true

require "spec_helper"

# Tests for freeze block detection and handling during merge operations
RSpec.describe "Freeze Block Detection and Handling" do
  describe "when template has freeze block but destination does not" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN_CONST = "template value"
        # kettle-dev:unfreeze

        def normal_method
          "normal"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        FROZEN_CONST = "dest value"

        def normal_method
          "normal"
        end
      RUBY
    end

    it "merges successfully when destination lacks freeze markers" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      # When template has freeze but dest doesn't, the freeze block behavior depends on implementation
      # The system should still merge successfully
      expect(result).to include("FROZEN_CONST")
      expect(result).to include("normal_method")
    end
  end

  describe "when destination has freeze block but template does not" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        FROZEN_CONST = "template value"

        def normal_method
          "normal"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN_CONST = "dest value"
        EXTRA_FROZEN = "extra"
        # kettle-dev:unfreeze

        def normal_method
          "normal"
        end
      RUBY
    end

    it "preserves destination freeze block" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("kettle-dev:freeze")
      expect(result).to include('FROZEN_CONST = "dest value"')
      expect(result).to include('EXTRA_FROZEN = "extra"')
      expect(result).to include("kettle-dev:unfreeze")
    end
  end

  describe "when both have freeze blocks with different content" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FIRST = "template"
        SECOND = "template"
        # kettle-dev:unfreeze
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FIRST = "dest"
        SECOND = "dest"
        THIRD = "dest only"
        # kettle-dev:unfreeze
      RUBY
    end

    it "preserves destination freeze block content" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include('FIRST = "dest"')
      expect(result).to include('SECOND = "dest"')
      expect(result).to include('THIRD = "dest only"')
      expect(result).not_to include('FIRST = "template"')
    end
  end

  describe "with nested freeze blocks" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        module Outer
          # kettle-dev:freeze
          CONST = "template"
          # kettle-dev:unfreeze

          class Inner
            def method
              "template"
            end
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        module Outer
          # kettle-dev:freeze
          CONST = "dest"
          EXTRA = "dest"
          # kettle-dev:unfreeze

          class Inner
            def method
              "dest"
            end

            def custom
              "custom"
            end
          end
        end
      RUBY
    end

    it "handles freeze blocks within modules and classes" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include('CONST = "dest"')
      expect(result).to include('EXTRA = "dest"')
      expect(result).to include("custom")
    end
  end

  describe "with freeze block containing only comments" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        # This is a comment
        # Another comment
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
        # Different comment
        # More comments
        CONST = "value"
        # kettle-dev:unfreeze

        def method
          "method"
        end
      RUBY
    end

    it "preserves destination freeze block even with only comments in template" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("Different comment")
      expect(result).to include('CONST = "value"')
    end
  end
end
