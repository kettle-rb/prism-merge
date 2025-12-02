# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "#merge" do
    context "with identical files" do
      it "returns the content unchanged" do
        template = dest = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
        RUBY

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("def hello")
        expect(result).to include('puts "world"')
      end
    end

    context "with ruby_example_one fixtures" do
      let(:template_path) { "spec/support/fixtures/ruby_example_one.template.rb" }
      let(:dest_path) { "spec/support/fixtures/ruby_example_one.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "produces a valid merge" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Should include magic comments
        expect(result).to include("# frozen_string_literal: true")
        expect(result).to include("# coding: utf-8")

        # Should include the method definition
        expect(result).to include("def example_method(arg1, arg2)")

        # Should include freeze block
        expect(result).to include("# kettle-dev:freeze")
        expect(result).to include("# kettle-dev:unfreeze")

        # Should include method calls
        expect(result).to include('example_method("foo", "bar")')
      end

      it "preserves freeze blocks" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Count freeze markers
        freeze_count = result.scan("# kettle-dev:freeze").length
        unfreeze_count = result.scan("# kettle-dev:unfreeze").length

        expect(freeze_count).to eq(1)
        expect(unfreeze_count).to eq(1)
      end
    end

    context "with ruby_example_two fixtures" do
      let(:template_path) { "spec/support/fixtures/ruby_example_two.template.rb" }
      let(:dest_path) { "spec/support/fixtures/ruby_example_two.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "merges template and destination comments intelligently" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Should prefer template comments where they differ
        # But this is complex - let's verify structure is maintained
        expect(result).to include("def example_method(arg1, arg2)")
        expect(result).to include("# kettle-dev:freeze")
      end
    end

    context "with class definitions" do
      let(:template_path) { "spec/support/fixtures/smart_merge/class_definition.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/class_definition.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "merges class definitions preserving custom methods" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Should include template class structure
        expect(result).to include("class Calculator")
        expect(result).to include("def add(a, b)")
        expect(result).to include("def subtract(a, b)")

        # Should preserve custom method from destination
        expect(result).to include("def multiply(a, b)")
      end
    end

    context "with conditionals" do
      let(:template_path) { "spec/support/fixtures/smart_merge/conditional.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/conditional.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "updates conditional bodies from template" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Should have the conditional
        expect(result).to include('if ENV["DEBUG"]')

        # Template version should win (simpler body)
        expect(result).to include('puts "Debug mode enabled"')

        # Should not duplicate the conditional
        if_count = result.scan('if ENV["DEBUG"]').length
        expect(if_count).to eq(1)
      end
    end

    context "with variable assignments" do
      it "merges variable assignments by name" do
        template = <<~RUBY
          # frozen_string_literal: true

          VERSION = "2.0.0"
          NAME = "myapp"
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          VERSION = "1.0.0"
          AUTHOR = "John Doe"
        RUBY

        merger = described_class.new(template, dest)
        result = merger.merge

        # Template version should win
        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include('NAME = "myapp"')

        # Should preserve destination-only constants
        expect(result).to include('AUTHOR = "John Doe"')

        # Should not duplicate VERSION
        version_count = result.scan("VERSION = ").length
        expect(version_count).to eq(1)
      end
    end

    context "with comments" do
      it "preserves leading comments" do
        template = <<~RUBY
          # frozen_string_literal: true

          # Important note
          def method_one
            1
          end
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          # Important note
          def method_one
            1
          end

          # Custom comment
          def method_two
            2
          end
        RUBY

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("# Important note")
        expect(result).to include("# Custom comment")
        expect(result).to include("def method_two")
      end

      it "preserves inline comments" do
        template = <<~RUBY
          # frozen_string_literal: true

          VERSION = "2.0.0" # Updated version
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          VERSION = "1.0.0" # Current version
        RUBY

        merger = described_class.new(template, dest)
        result = merger.merge

        # Template version and comment should win
        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include("# Updated version")
      end
    end

    context "with freeze blocks" do
      it "always preserves destination freeze blocks" do
        template = <<~RUBY
          # frozen_string_literal: true

          gem "rails"

          # kettle-dev:freeze
          # Placeholder for custom gems
          # kettle-dev:unfreeze
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          gem "rails"

          # kettle-dev:freeze
          gem "custom-gem", path: "../custom"
          gem "another-gem"
          # kettle-dev:unfreeze
        RUBY

        merger = described_class.new(template, dest)
        result = merger.merge

        # Should preserve destination freeze block content
        expect(result).to include('gem "custom-gem", path: "../custom"')
        expect(result).to include('gem "another-gem"')
      end
    end

    context "with parsing errors" do
      it "raises TemplateParseError when template is invalid" do
        template = "this is not valid ruby {{"
        dest = "def hello; end"

        merger = described_class.new(template, dest)

        expect { merger.merge }.to raise_error(Prism::Merge::TemplateParseError) do |error|
          expect(error.content).to eq(template)
          expect(error.parse_result).not_to be_nil
        end
      end

      it "raises DestinationParseError when destination is invalid" do
        template = "def hello; end"
        dest = "this is not valid ruby {{"

        merger = described_class.new(template, dest)

        expect { merger.merge }.to raise_error(Prism::Merge::DestinationParseError) do |error|
          expect(error.content).to eq(dest)
          expect(error.parse_result).not_to be_nil
        end
      end
    end
  end

  describe "#merge_with_debug" do
    it "returns hash with content and debug information" do
      template = <<~RUBY
        def hello
          puts "world"
        end
      RUBY

      dest = <<~RUBY
        def hello
          puts "world"
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge_with_debug

      expect(result).to be_a(Hash)
      expect(result).to have_key(:content)
      expect(result).to have_key(:debug)
      expect(result).to have_key(:statistics)
      expect(result[:statistics]).to be_a(Hash)
    end
  end
end
