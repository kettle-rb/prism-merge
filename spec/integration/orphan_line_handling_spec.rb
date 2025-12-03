# frozen_string_literal: true

require "spec_helper"

# Tests for handling orphan lines (comments and blank lines between nodes)
RSpec.describe "Orphan Line Handling" do
  describe "with orphan comments between nodes" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def first_method
          "first"
        end

        # Orphan comment in template

        def second_method
          "second"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def first_method
          "first"
        end

        # Different orphan comment in dest
        # Another orphan line

        def second_method
          "second"
        end
      RUBY
    end

    it "handles orphan comments between matching nodes" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("first_method")
      expect(result).to include("second_method")
      # Should handle orphan comments
      expect(result).to include("comment")
    end
  end

  describe "with orphan blank lines" do
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

    it "preserves appropriate blank line spacing" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      # Result should have reasonable spacing
      expect(result.scan(/\n\n+/).map(&:length).max).to be <= 3
    end
  end
end
