# frozen_string_literal: true

# Regression specs for magic comment handling during merge operations.
#
# Magic comments (frozen_string_literal, encoding, etc.) must always remain
# at the top of Ruby files. These specs verify that our merge logic preserves
# this requirement in various scenarios.

RSpec.describe Prism::Merge::SmartMerger, type: :integration do
  describe "magic comment handling" do
    # Helper to perform merge with SmartMerger
    def merge(template:, destination:, preference: :template)
      merger = described_class.new(
        template,
        destination,
        preference: preference,
      )
      merger.merge
    end

    describe "comment-only files" do
      context "when template has magic comment and destination doesn't" do
        let(:template) do
          <<~RUBY
            # frozen_string_literal: true

            # Template comment
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # Destination comment
          RUBY
        end

        it "preserves magic comment at top with template preference" do
          result = merge(template: template, destination: destination, preference: :template)
          lines = result.lines

          # Magic comment should be first non-empty line
          first_content_line = lines.find { |l| !l.strip.empty? }
          expect(first_content_line).to match(/frozen_string_literal/)
        end

        it "keeps the destination comment-only content unchanged with destination preference" do
          result = merge(template: template, destination: destination, preference: :destination)

          expect(result).to eq(<<~RUBY)
            # Destination comment
          RUBY
        end
      end

      context "when destination has magic comment and template doesn't" do
        let(:template) do
          <<~RUBY
            # Template comment
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # frozen_string_literal: true

            # Destination comment
          RUBY
        end

        it "preserves destination's magic comment at top with destination preference" do
          result = merge(template: template, destination: destination, preference: :destination)
          lines = result.lines

          first_content_line = lines.find { |l| !l.strip.empty? }
          expect(first_content_line).to match(/frozen_string_literal/)
        end

        it "preserves destination's magic comment at top with template preference" do
          result = merge(template: template, destination: destination, preference: :template)
          expect(result).to eq(<<~RUBY)
            # frozen_string_literal: true

          RUBY
        end
      end

      context "when both have magic comments" do
        let(:template) do
          <<~RUBY
            # frozen_string_literal: true

            # Template comment
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # frozen_string_literal: false

            # Destination comment
          RUBY
        end

        it "uses template's magic comment with template preference" do
          result = merge(template: template, destination: destination, preference: :template)
          expect(result).to eq(<<~RUBY)
            # frozen_string_literal: false

          RUBY
        end

        it "uses destination's magic comment with destination preference" do
          result = merge(template: template, destination: destination, preference: :destination)
          lines = result.lines

          first_content_line = lines.find { |l| !l.strip.empty? }
          expect(first_content_line).to match(/frozen_string_literal: false/)
        end

        it "does not duplicate magic comments" do
          result = merge(template: template, destination: destination, preference: :template)
          magic_comment_count = result.scan("frozen_string_literal").size
          expect(magic_comment_count).to eq(1)
          expect(result).to include("frozen_string_literal: false")
          expect(result).not_to include("frozen_string_literal: true")
        end
      end

      context "when destination has shebang plus magic comment and template doesn't" do
        let(:template) do
          <<~RUBY
            # Template comment
          RUBY
        end

        let(:destination) do
          <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: true

            # Destination comment
          RUBY
        end

        it "preserves shebang before the destination magic comment with template preference" do
          result = merge(template: template, destination: destination, preference: :template)

          expect(result).to eq(<<~RUBY)
            #!/usr/bin/env ruby
            # frozen_string_literal: true

          RUBY
        end
      end

      context "when magic comment appears later in template (invalid position)" do
        let(:template) do
          <<~RUBY
            # Some comment first

            # frozen_string_literal: true

            # Another comment
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # Destination comment
          RUBY
        end

        it "does not treat the misplaced comment specially under template preference" do
          result = merge(template: template, destination: destination, preference: :template)

          expect(result).to eq("\n")
        end
      end
    end

    describe "files with Ruby code" do
      context "when merging classes with magic comments" do
        let(:template) do
          <<~RUBY
            # frozen_string_literal: true

            class Foo
              def bar
                "template"
              end
            end
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # frozen_string_literal: true

            class Foo
              def baz
                "destination"
              end
            end
          RUBY
        end

        it "preserves magic comment at top after merge" do
          result = merge(template: template, destination: destination, preference: :template)
          lines = result.lines

          first_content_line = lines.find { |l| !l.strip.empty? }
          expect(first_content_line).to match(/frozen_string_literal/)
        end

        it "magic comment appears before class definition" do
          result = merge(template: template, destination: destination, preference: :template)

          magic_pos = result.index("frozen_string_literal")
          class_pos = result.index("class Foo")

          expect(magic_pos).to be < class_pos
        end

        it "keeps destination magic comment value when template preference differs" do
          template = <<~RUBY
            # frozen_string_literal: true

            class Foo
            end
          RUBY

          destination = <<~RUBY
            # frozen_string_literal: false

            class Foo
            end
          RUBY

          result = merge(template: template, destination: destination, preference: :template)

          expect(result).to start_with("# frozen_string_literal: false\n\n")
        end

        it "preserves a destination shebang before destination magic comments" do
          template = <<~RUBY
            class Foo
            end
          RUBY

          destination = <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: false

            class Foo
            end
          RUBY

          result = merge(template: template, destination: destination, preference: :template)

          expect(result).to start_with("#!/usr/bin/env ruby\n# frozen_string_literal: false\n\n")
        end

        it "keeps a misplaced template header-like comment as an ordinary comment after the destination header" do
          template = <<~RUBY
            # Some comment first
            # frozen_string_literal: true

            class Foo
            end
          RUBY

          destination = <<~RUBY
            # frozen_string_literal: false

            class Foo
            end
          RUBY

          result = merge(template: template, destination: destination, preference: :template)

          expect(result).to eq(<<~RUBY)
            # frozen_string_literal: false

            # Some comment first
            # frozen_string_literal: true

            class Foo
            end
          RUBY
        end
      end

      context "with block leading magic comment that might be reordered" do
        # This tests the scenario where merge logic might try to reorder
        # a comment block that contains the magic comment

        let(:template) do
          <<~RUBY
            # frozen_string_literal: true
            # Template header comment

            class Foo
            end
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # Destination header comment
            # Another destination line

            # frozen_string_literal: true

            class Foo
              def added_method
              end
            end
          RUBY
        end

        it "does not place code above magic comment" do
          result = merge(template: template, destination: destination, preference: :destination)

          # Find position of magic comment and any code
          magic_pos = result.index("frozen_string_literal")
          class_pos = result.index("class ")
          def_pos = result.index("def ")

          # Magic comment should come before any Ruby code
          expect(magic_pos).to be < class_pos if class_pos
          expect(magic_pos).to be < def_pos if def_pos
        end

        it "preserves the destination's existing header ordering without duplicating magic comments" do
          result = merge(template: template, destination: destination, preference: :destination)

          expect(result).to eq(<<~RUBY)
            # Destination header comment
            # Another destination line

            # frozen_string_literal: true

            class Foo
              def added_method
              end
            end
          RUBY
          expect(result.scan("frozen_string_literal").size).to eq(1)
        end
      end

      context "with multiple magic comments (encoding + frozen_string_literal)" do
        let(:template) do
          <<~RUBY
            # encoding: UTF-8
            # frozen_string_literal: true

            class Foo
            end
          RUBY
        end

        let(:destination) do
          <<~RUBY
            # frozen_string_literal: true

            class Foo
              def bar
              end
            end
          RUBY
        end

        it "preserves all magic comments at top" do
          result = merge(template: template, destination: destination, preference: :template)

          encoding_pos = result.index("encoding:")
          frozen_pos = result.index("frozen_string_literal")
          class_pos = result.index("class ")

          # Both magic comments should be before class
          expect(encoding_pos).to be < class_pos if encoding_pos
          expect(frozen_pos).to be < class_pos
        end
      end
    end
  end
end
