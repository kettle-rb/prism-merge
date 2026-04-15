# frozen_string_literal: true

require "prism/merge"

RSpec.describe Prism::Merge::PartialTemplateMerger, :prism_backend do
  describe "#merge" do
    it "replaces the anchored top-level class while preserving surrounding source" do
      template = <<~RUBY
        class Example
          def template_method
            :template
          end
        end
      RUBY

      destination = <<~RUBY
        # Before

        class Example
          def old_method
            :old
          end
        end

        # After
      RUBY

      result = described_class.new(
        template: template,
        destination: destination,
        anchor: {type: :class, text: /class Example/},
        replace_mode: true,
      ).merge

      expect(result.section_found?).to be(true)
      expect(result.changed).to be(true)
      expect(result.content).to eq(<<~RUBY)
        # Before

        class Example
          def template_method
            :template
          end
        end

        # After
      RUBY
    end

    it "merges the anchored class through Prism::Merge::SmartMerger when replace_mode is false" do
      template = <<~RUBY
        class Example
          def template_method
            :template
          end
        end
      RUBY

      destination = <<~RUBY
        class Example
          def custom_method
            :custom
          end
        end
      RUBY

      result = described_class.new(
        template: template,
        destination: destination,
        anchor: {type: :class, text: /class Example/},
        add_missing: true,
      ).merge

      expect(result.section_found?).to be(true)
      expect(result.changed).to be(true)
      expect(result.content).to include("def template_method")
      expect(result.content).to include("def custom_method")
    end

    it "forwards corruption handling into the anchored smart merger" do
      template = <<~RUBY
        class Example
          # Shared header

          def shared
            :template
          end
        end
      RUBY

      destination = <<~RUBY
        class Example
          # Shared header
          # Shared header
          # Destination header
          def shared
            :destination
          end
        end
      RUBY

      expect do
        described_class.new(
          template: template,
          destination: destination,
          anchor: {type: :class, text: /class Example/},
          preference: :destination,
          add_missing: true,
          corruption_handling: :error,
        ).merge
      end.to raise_error(Prism::Merge::CorruptionDetectedError, /duplicate_template_leading_prefix/)
    end

    it "uses the boundary statement to limit replacement to the intended top-level section" do
      template = <<~RUBY
        def first_method
          :template
        end
      RUBY

      destination = <<~RUBY
        def first_method
          :old
        end

        def second_method
          :keep
        end
      RUBY

      result = described_class.new(
        template: template,
        destination: destination,
        anchor: {type: :def, text: /first_method/},
        boundary: {type: :def, text: /second_method/},
        replace_mode: true,
      ).merge

      expect(result.content).to eq(<<~RUBY)
        def first_method
          :template
        end

        def second_method
          :keep
        end
      RUBY
    end

    it "appends the template when the anchor is missing and when_missing is append" do
      template = <<~RUBY
        class Added
        end
      RUBY

      destination = <<~RUBY
        class Existing
        end
      RUBY

      result = described_class.new(
        template: template,
        destination: destination,
        anchor: {type: :class, text: /class Added/},
        when_missing: :append,
      ).merge

      expect(result.section_found?).to be(false)
      expect(result.changed).to be(true)
      expect(result.content).to eq(<<~RUBY)
        class Existing
        end

        class Added
        end
      RUBY
    end
  end
end
