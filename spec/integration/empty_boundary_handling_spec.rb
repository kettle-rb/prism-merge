# frozen_string_literal: true

require "spec_helper"

# Tests for handling empty content in boundaries
RSpec.describe "Empty Boundary Handling" do
  describe "when template boundary is empty" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Start marker
        # End marker

        def method_after
          "after"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Start marker
        def method_between
          "between"
        end
        # End marker

        def method_after
          "after"
        end
      RUBY
    end

    it "uses destination content when template boundary is empty" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("method_between")
      expect(result).to include("method_after")
    end
  end

  describe "when destination boundary is empty" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Start marker
        def method_between
          "between"
        end
        # End marker

        def method_after
          "after"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Start marker
        # End marker

        def method_after
          "after"
        end
      RUBY
    end

    it "uses template content when destination boundary is empty" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to include("method_between")
      expect(result).to include("method_after")
    end
  end

  describe "when both boundaries are empty" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_before
          "before"
        end

        # Empty section here

        def method_after
          "after"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_before
          "before"
        end

        # Empty section here

        def method_after
          "after"
        end
      RUBY
    end

    it "handles both empty boundaries gracefully" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("method_before")
      expect(result).to include("method_after")
    end
  end

  describe "when template has only comments in boundary" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Section start
        # Just comments
        # No actual code
        # Section end

        def method
          "method"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Section start
        CONST = "value"
        # Section end

        def method
          "method"
        end
      RUBY
    end

    it "treats comment-only template as empty for node purposes" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("CONST")
      expect(result).to include("method")
    end
  end
end
