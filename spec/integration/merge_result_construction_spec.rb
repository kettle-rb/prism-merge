# frozen_string_literal: true

require "spec_helper"

# Tests for merge result construction and edge cases
RSpec.describe "Merge Result Construction" do
  describe "with many consecutive conflicts" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        A = "template_a"
        B = "template_b"
        C = "template_c"
        D = "template_d"
        E = "template_e"
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        A = "dest_a"
        B = "dest_b"
        C = "dest_c"
        D = "dest_d"
        E = "dest_e"
      RUBY
    end

    it "handles many consecutive signature matches" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        preference: :destination,
      )
      result = merger.merge

      # All destination values should be used
      expect(result).to include("dest_a")
      expect(result).to include("dest_b")
      expect(result).to include("dest_c")
      expect(result).to include("dest_d")
      expect(result).to include("dest_e")
    end
  end

  describe "with alternating template-only and matched nodes" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        A = "matched"
        B = "template_only"
        C = "matched"
        D = "template_only"
        E = "matched"
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        A = "matched"
        C = "matched"
        E = "matched"
      RUBY
    end

    it "handles alternating template-only and matched nodes" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to include("A")
      expect(result).to include("B")
      expect(result).to include("C")
      expect(result).to include("D")
      expect(result).to include("E")
    end
  end

  describe "with complex merge decisions" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Template comment
        def method_a
          "template"
        end

        # Another comment
        def method_b
          "template"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # Dest comment
        def method_a
          "dest"
        end

        def custom_method
          "custom"
        end

        # Different comment
        def method_b
          "dest"
        end
      RUBY
    end

    it "tracks line origins correctly" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      expect(result).to include("custom_method")
    end
  end
end
