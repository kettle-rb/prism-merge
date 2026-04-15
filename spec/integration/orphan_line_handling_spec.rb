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

    it "prefers template orphan comments when both sides retain the surrounding owners" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, preference: :template)
      result = merger.merge

      expect(result).to eq(<<~RUBY)
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

    it "preserves destination orphan blank-line spacing" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
      result = merger.merge

      expect(result).to eq(dest_code)
    end
  end

  describe "when a destination-only owner is removed" do
    let(:template_code) do
      <<~RUBY
        def first_method
          :template
        end

        def third_method
          :template
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        def first_method
          :destination
        end

        # docs for removed second_method
        def second_method
          :destination_only
        end

        def third_method
          :destination
        end
      RUBY
    end

    it "re-homes the removed owner's comment block onto the previous retained sibling" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        preference: :template,
        remove_template_missing_nodes: true,
      )

      expect(merger.merge).to eq(<<~RUBY)
        def first_method
          :template
        end

        # docs for removed second_method

        def third_method
          :template
        end
      RUBY
    end
  end

  describe "when multiple destination-only owners are removed" do
    let(:template_code) do
      <<~RUBY
        def first_method
          :template
        end

        def fourth_method
          :template
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        def first_method
          :destination
        end

        # docs for removed second_method
        def second_method
          :destination_only
        end

        # docs for removed third_method
        def third_method
          :destination_only
        end

        def fourth_method
          :destination
        end
      RUBY
    end

    it "keeps multiple orphan comment regions ordered between the retained siblings" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        preference: :template,
        remove_template_missing_nodes: true,
      )

      expect(merger.merge).to eq(<<~RUBY)
        def first_method
          :template
        end

        # docs for removed second_method

        # docs for removed third_method

        def fourth_method
          :template
        end
      RUBY
    end
  end
end
