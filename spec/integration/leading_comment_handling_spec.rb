# frozen_string_literal: true

require "spec_helper"

# Tests for handling leading comments on nodes
RSpec.describe "Leading Comment Handling" do
  describe "when next node has leading comments" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end

        # Leading comment for method_b
        # Another comment
        def method_b
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "dest_a"
        end


        # Different leading comment for method_b
        # More comments
        def method_b
          "dest_b"
        end
      RUBY
    end

    it "correctly handles blank lines before leading comments" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      expect(result).to include("leading comment")
    end
  end

  describe "when nodes have multiple leading comment blocks" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end

        # Block 1
        # Block 1 continued

        # Block 2
        def method_b
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "dest_a"
        end


        # Different block 1
        # Different block 1 continued

        # Different block 2
        def method_b
          "dest_b"
        end
      RUBY
    end

    it "handles multiple leading comment blocks" do
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

  describe "when some nodes have comments and others don't" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Comment for method_a
        def method_a
          "a"
        end

        def method_b
          "b"
        end

        # Comment for method_c
        def method_c
          "c"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Different comment for method_a
        def method_a
          "dest_a"
        end


        def method_b
          "dest_b"
        end

        # Different comment for method_c
        def method_c
          "dest_c"
        end
      RUBY
    end

    it "handles mixed commented and uncommented nodes" do
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

  describe "when node has inline and leading comments" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end

        # Leading comment
        def method_b # inline comment
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "dest_a"
        end


        # Different leading comment
        def method_b # different inline comment
          "dest_b"
        end
      RUBY
    end

    it "handles both inline and leading comments" do
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

  describe "when trailing blank lines encounter leading comments" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "a"
        end


        # This is a leading comment
        def method_b
          "b"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a
          "dest_a"
        end



        # This is a dest leading comment
        def method_b
          "dest_b"
        end
      RUBY
    end

    it "stops counting blank lines at leading comments" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      expect(result).to include("leading comment")
    end
  end
end
