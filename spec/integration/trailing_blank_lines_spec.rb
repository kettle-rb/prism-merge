# frozen_string_literal: true

require "spec_helper"

# Tests for handling trailing blank lines between nodes
RSpec.describe "Trailing Blank Line Handling" do
  describe "with trailing blank lines after matched nodes" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end


        def method_b
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end



        def method_b
          "b"
        end
      RUBY
    end

    it "preserves destination trailing blank lines for matched nodes" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      # Should have blank lines between methods
      expect(result).to match(/method_a.*\n\s*\n.*method_b/m)
    end
  end

  describe "with last node having trailing blanks" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end


      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end



      RUBY
    end

    it "handles trailing blanks at end of file" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("method_a")
    end
  end

  describe "with comments between nodes and blank lines" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end

        # Comment about method_b

        def method_b
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end


        # Different comment about method_b

        def method_b
          "b"
        end
      RUBY
    end

    it "handles blank lines with comments correctly" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      expect(result).to include("comment")
    end
  end

  describe "with no blank lines between nodes in destination" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end


        def method_b
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end
        def method_b
          "b"
        end
      RUBY
    end

    it "respects destination spacing (no blanks)" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
    end
  end

  describe "with mixed blank line patterns" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end

        def method_b
          "b"
        end


        def method_c
          "c"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end


        def method_b
          "b"
        end

        def method_c
          "c"
        end
      RUBY
    end

    it "handles mixed blank line patterns between methods" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      expect(result).to include("method_c")
    end
  end
end
