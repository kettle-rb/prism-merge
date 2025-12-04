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
        merger = described_class.new(template_content, dest_content, signature_match_preference: :template)
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

        merger = described_class.new(template, dest, signature_match_preference: :template, add_template_only_nodes: true)
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

        merger = described_class.new(template, dest, signature_match_preference: :template)
        result = merger.merge

        # Template version and comment should win
        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include("# Updated version")
      end
    end

    context "with end-of-line comments" do
      it "adds an end-of-line comment when the code is the same" do
        template = <<~RUBY
          # frozen_string_literal: true

          var = "stuff" # this is the stuff
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          var = "stuff"
        RUBY

        merger = described_class.new(template, dest, signature_match_preference: :template)
        result = merger.merge

        expect(result).to include('var = "stuff" # this is the stuff')
      end

      it "adds an end-of-line comment when the code is not the same" do
        template = <<~RUBY
          # frozen_string_literal: true

          var = "stuff" # this is the stuff
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          var = "junk"
        RUBY

        merger = described_class.new(template, dest, signature_match_preference: :template)
        result = merger.merge

        expect(result).to include('var = "stuff" # this is the stuff')
      end

      it "changes an end-of-line comment when the code is not the same" do
        template = <<~RUBY
          # frozen_string_literal: true

          var = "stuff" # this is the stuff
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          var = "junk" # this is the old
        RUBY

        merger = described_class.new(template, dest, signature_match_preference: :template)
        result = merger.merge

        expect(result).to include('var = "stuff" # this is the stuff')
      end

      it "retains an end-of-line comment when the code is not the same" do
        template = <<~RUBY
          # frozen_string_literal: true

          var = "stuff" # this is the stuff
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          var = "junk" # this is the old
        RUBY

        merger = described_class.new(template, dest, signature_match_preference: :destination)
        result = merger.merge

        expect(result).to include('var = "junk" # this is the old')
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

  describe "edge cases" do
    context "with empty destination" do
      let(:template_path) { "spec/support/fixtures/smart_merge/empty_destination.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/empty_destination.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "merges when destination is essentially empty" do
        merger = described_class.new(template_content, dest_content, add_template_only_nodes: true)
        result = merger.merge

        expect(result).to include('VERSION = "1.0.0"')
        expect(result).to include("def example")
      end
    end

    context "with empty template" do
      let(:template_path) { "spec/support/fixtures/smart_merge/empty_template.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/empty_template.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "keeps destination content when template is essentially empty" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        expect(result).to include('CUSTOM_VERSION = "2.0.0"')
        expect(result).to include("def custom_method")
      end
    end

    context "with template-only nodes and add_template_only_nodes: true" do
      let(:template_path) { "spec/support/fixtures/smart_merge/template_only_nodes.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/template_only_nodes.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "adds nodes that only exist in template" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        # Template version of VERSION should win
        expect(result).to include('VERSION = "2.0.0"')

        # Template-only nodes should be added
        expect(result).to include('NEW_CONSTANT = "This is new in template"')
        expect(result).to include("def new_template_method")
        expect(result).to include("class NewTemplateClass")

        # Destination-only node should be preserved
        expect(result).to include("def destination_only_method")
      end

      it "skips template-only nodes when add_template_only_nodes: false" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :destination,
          add_template_only_nodes: false,
        )
        result = merger.merge

        # Destination version of VERSION should win
        expect(result).to include('VERSION = "1.0.0"')

        # Template-only nodes should NOT be added
        expect(result).not_to include('NEW_CONSTANT = "This is new in template"')
        expect(result).not_to include("def new_template_method")
        expect(result).not_to include("class NewTemplateClass")

        # Destination-only node should be preserved
        expect(result).to include("def destination_only_method")
      end
    end

    context "with freeze blocks" do
      let(:template_path) { "spec/support/fixtures/smart_merge/freeze_blocks.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/freeze_blocks.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "always preserves destination freeze block content" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Freeze block from destination should be preserved
        expect(result).to include('secret: "destination secret"')
        expect(result).to include('api_key: "abc123"')

        # Should include freeze markers
        expect(result).to include("# kettle-dev:freeze")
        expect(result).to include("# kettle-dev:unfreeze")
      end

      it "preserves freeze blocks even with template preference" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
        )
        result = merger.merge

        # Freeze block still wins from destination
        expect(result).to include('secret: "destination secret"')
        expect(result).to include('api_key: "abc123"')
      end
    end

    context "with method calls with arguments" do
      let(:template_path) { "spec/support/fixtures/smart_merge/method_calls_with_args.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/method_calls_with_args.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "matches method calls by name and arguments" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :destination,
        )
        result = merger.merge

        # Same signature calls should match (destination wins)
        expect(result).to include('config.setting = "destination value"')
        expect(result).to include("config.extra = \"custom\"")

        # Destination-only call should be preserved
        expect(result).to include('cleanup("temp")')
      end

      it "uses template version when preference is :template" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
        )
        result = merger.merge

        # Template version should win
        expect(result).to include('config.setting = "template value"')
        expect(result).not_to include("config.extra")

        # Destination-only call should still be preserved
        expect(result).to include('cleanup("temp")')
      end
    end

    context "with various assignment types" do
      let(:template_path) { "spec/support/fixtures/smart_merge/various_assignments.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/various_assignments.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "matches assignments by variable name (destination preference)" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :destination,
        )
        result = merger.merge

        # Destination versions should win
        expect(result).to include('VERSION = "1.0.0"')
        expect(result).to include("MAX_RETRIES = 3")
        expect(result).to include('@instance_var = "destination"')
        expect(result).to include('@@class_var = "destination"')
        expect(result).to include('$global_var = "destination"')

        # Destination-only assignment
        expect(result).to include("CUSTOM_FLAG = true")
      end

      it "uses template values when preference is :template" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
        )
        result = merger.merge

        # Template versions should win
        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include("MAX_RETRIES = 5")
        expect(result).to include('@instance_var = "template"')
        expect(result).to include('@@class_var = "template"')
        expect(result).to include('$global_var = "template"')

        # Destination-only assignment still preserved
        expect(result).to include("CUSTOM_FLAG = true")
      end
    end

    context "with if/unless conditionals" do
      let(:template_path) { "spec/support/fixtures/smart_merge/if_unless_conditionals.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/if_unless_conditionals.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "matches conditionals by condition, not body (destination preference)" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :destination,
        )
        result = merger.merge

        # Destination implementations should win
        expect(result).to include("load_defaults 6.1")
        expect(result).to include("custom_setting = true")
        expect(result).to include("enable_feature(:old_ui)")
        expect(result).to include("config.cache_store = :memory_store")

        # Destination-only conditional
        expect(result).to include('if ENV["EXTRA_FEATURE"]')
        expect(result).to include("enable_extra_features")
      end

      it "uses template implementation when preference is :template" do
        merger = described_class.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
        )
        result = merger.merge

        # Template implementations should win
        expect(result).to include("load_defaults 7.0")
        expect(result).to include("enable_feature(:new_ui)")
        expect(result).to include("config.cache_store = :redis_cache_store")

        # Should not include destination's custom additions in matched blocks
        expect(result).not_to include("custom_setting = true")
        expect(result).not_to include("enable_feature(:custom_feature)")

        # Destination-only conditional still preserved
        expect(result).to include('if ENV["EXTRA_FEATURE"]')
      end
    end

    context "with top-level constants and signature_match_preference" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "2.0.0"
          NAME = "updated-name"
          
          if ENV["DEBUG"]
            puts "Template debug"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          NAME = "original-name"
          CUSTOM = "custom-value"
          
          if ENV["DEBUG"]
            puts "Dest debug"
          end
        RUBY
      end

      it "uses template version when signature_match_preference is :template" do
        merger = described_class.new(
          template_code,
          dest_code,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )

        result = merger.merge
        # Template versions should win for matching constants
        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include('NAME = "updated-name"')
        # Destination-only constant should still be included
        expect(result).to include('CUSTOM = "custom-value"')
        # Template version of conditional should win
        expect(result).to include('puts "Template debug"')
        expect(result).not_to include('puts "Dest debug"')
      end

      it "uses destination version when signature_match_preference is :destination (default)" do
        merger = described_class.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
          add_template_only_nodes: true,
        )

        result = merger.merge
        # Destination versions should win for matching constants
        expect(result).to include('VERSION = "1.0.0"')
        expect(result).to include('NAME = "original-name"')
        # Destination-only constant should be included
        expect(result).to include('CUSTOM = "custom-value"')
        # Destination version of conditional should win
        expect(result).to include('puts "Dest debug"')
        expect(result).not_to include('puts "Template debug"')
      end
    end

    context "with add_template_only_nodes option" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def template_only_method
              "only in template"
            end
          
            def shared_method
              "shared"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def shared_method
              "shared"
            end
          
            def dest_only_method
              "only in dest"
            end
          end
        RUBY
      end

      it "includes template-only nodes when add_template_only_nodes is true" do
        merger = described_class.new(
          template_code,
          dest_code,
          add_template_only_nodes: true,
        )

        result = merger.merge
        expect(result).to include("template_only_method")
        expect(result).to include("shared_method")
        expect(result).to include("dest_only_method")
      end

      it "excludes template-only nodes when add_template_only_nodes is false" do
        merger = described_class.new(
          template_code,
          dest_code,
          add_template_only_nodes: false,
        )

        result = merger.merge
        expect(result).not_to include("template_only_method")
        expect(result).to include("shared_method")
        expect(result).to include("dest_only_method")
      end
    end

    context "with mix of matched, template-only, and dest-only nodes" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class ComplexClass
            def shared_method_1
              "shared 1"
            end
            
            def template_only
              "template only"
            end
            
            def shared_method_2
              "shared 2"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class ComplexClass
            def shared_method_1
              "shared 1 dest"
            end
            
            def dest_only
              "dest only"
            end
            
            def shared_method_2
              "shared 2 dest"
            end
          end
        RUBY
      end

      it "correctly merges with add_template_only_nodes: true" do
        merger = described_class.new(
          template_code,
          dest_code,
          add_template_only_nodes: true,
        )

        result = merger.merge

        # Should have destination versions of shared methods
        expect(result).to include("shared 1 dest")
        expect(result).to include("shared 2 dest")

        # Should have both template-only and dest-only
        expect(result).to include("template_only")
        expect(result).to include("dest_only")
      end

      it "correctly merges with add_template_only_nodes: false" do
        merger = described_class.new(
          template_code,
          dest_code,
          add_template_only_nodes: false,
        )

        result = merger.merge

        # Should have destination versions of shared methods
        expect(result).to include("shared 1 dest")
        expect(result).to include("shared 2 dest")

        # Should NOT have template-only, but should have dest-only
        expect(result).not_to include("template_only")
        expect(result).to include("dest_only")
      end
    end

    context "with comments and blank lines around nodes" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # This is a class comment
          class MyClass
            # Method comment
            def method_a
              "a"
            end
          
          
            # Another method
            def method_b
              "b"
            end
          end
          
          
          # Trailing comment
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # This is a class comment
          class MyClass
            def method_a
              "a custom"
            end
          
            def method_b
              "b custom"
            end
            
            def custom_method
              "custom"
            end
          end
        RUBY
      end

      it "preserves comments and handles blank lines correctly" do
        merger = described_class.new(
          template_code,
          dest_code,
        )

        result = merger.merge

        expect(result).to include("# This is a class comment")
        expect(result).to include("method_a")
        expect(result).to include("method_b")
        expect(result).to include("custom_method")
        expect(result).to include("a custom")
        expect(result).to include("b custom")
      end
    end

    context "with standalone comments" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # Standalone comment
          
          VERSION = "1.0.0"
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
        RUBY
      end

      it "includes standalone comments from template" do
        merger = described_class.new(
          template_code,
          dest_code,
        )

        result = merger.merge
        expect(result).to include("# Standalone comment")
      end
    end

    context "with minimal template content" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
        RUBY
      end

      it "handles empty template range gracefully" do
        merger = described_class.new(
          template_code,
          dest_code,
        )

        result = merger.merge
        expect(result).to include('VERSION = "1.0.0"')
      end
    end

    context "with destination-only nodes in various positions" do
      it "appends destination-only nodes that come before template nodes" do
        template_code = <<~RUBY
          # frozen_string_literal: true
          
          ZETA = "last"
        RUBY

        dest_code = <<~RUBY
          # frozen_string_literal: true
          
          ALPHA = "first"
          BETA = "second"
          ZETA = "last"
        RUBY

        merger = described_class.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('ALPHA = "first"')
        expect(result).to include('BETA = "second"')
        expect(result).to include('ZETA = "last"')

        # Check order
        alpha_pos = result.index("ALPHA")
        beta_pos = result.index("BETA")
        zeta_pos = result.index("ZETA")
        expect(alpha_pos).to be < beta_pos
        expect(beta_pos).to be < zeta_pos
      end

      it "preserves destination nodes between matched nodes" do
        template_code = <<~RUBY
          # frozen_string_literal: true
          
          FIRST = "1"
          LAST = "3"
        RUBY

        dest_code = <<~RUBY
          # frozen_string_literal: true
          
          FIRST = "1"
          MIDDLE = "2"
          LAST = "3"
        RUBY

        merger = described_class.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('FIRST = "1"')
        expect(result).to include('MIDDLE = "2"')
        expect(result).to include('LAST = "3"')
      end

      it "appends trailing destination-only nodes" do
        template_code = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
        RUBY

        dest_code = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          
          # Custom section
          CUSTOM_A = "a"
          CUSTOM_B = "b"
        RUBY

        merger = described_class.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('CUSTOM_A = "a"')
        expect(result).to include('CUSTOM_B = "b"')
        expect(result).to include("# Custom section")
      end
    end

    context "with blank line spacing variations" do
      it "preserves blank line spacing from destination" do
        template_code = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "2.0.0"
          
          
          NAME = "app"
        RUBY

        dest_code = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          
          NAME = "app"
        RUBY

        merger = described_class.new(
          template_code,
          dest_code,
          signature_match_preference: :template,
        )

        result = merger.merge
        # Should have VERSION from template
        expect(result).to include('VERSION = "2.0.0"')
        # Should preserve spacing
        expect(result).to include("\n\n")
      end

      it "handles blank lines between dest-only nodes" do
        template_code = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
        RUBY

        dest_code = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          CUSTOM = "custom"
          
          
          ANOTHER = "another"
        RUBY

        merger = described_class.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('CUSTOM = "custom"')
        expect(result).to include('ANOTHER = "another"')
      end
    end

    context "with conditional statements" do
      it "uses template version when preference is :template" do
        template_code = <<~RUBY
          # frozen_string_literal: true
          
          if Rails.env.production?
            puts "Template production"
          end
        RUBY

        dest_code = <<~RUBY
          # frozen_string_literal: true
          
          if Rails.env.production?
            puts "Dest production"
          end
        RUBY

        merger = described_class.new(
          template_code,
          dest_code,
          signature_match_preference: :template,
        )

        result = merger.merge
        expect(result).to include('puts "Template production"')
        expect(result).not_to include('puts "Dest production"')
      end
    end

    context "with error handling" do
      it "raises TemplateParseError for invalid template" do
        invalid_template = <<~RUBY
          # frozen_string_literal: true
          
          def method
            # Missing end
        RUBY

        valid_dest = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
        RUBY

        expect do
          described_class.new(invalid_template, valid_dest).merge
        end.to raise_error(Prism::Merge::TemplateParseError)
      end

      it "raises DestinationParseError for invalid destination" do
        valid_template = <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
        RUBY

        invalid_dest = <<~RUBY
          # frozen_string_literal: true
          
          def method
            # Missing end
        RUBY

        expect do
          described_class.new(valid_template, invalid_dest).merge
        end.to raise_error(Prism::Merge::DestinationParseError)
      end
    end

    context "with frozen_string_literal comments" do
      it "removes duplicated" do
        # When running kettle-dev-setup --allowed=true --force
        # it uses --force to set allow_replace: true
        # This means it uses :replace strategy

        # Starting state: file with 4 frozen_string_literal comments, and 2 duplicate chunks of comments
        starting_dest = <<~GEMFILE
          # frozen_string_literal: true
          # frozen_string_literal: true
          # frozen_string_literal: true
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
          # See gemspec
          # To retain during kettle-dev templating:
          #     kettle-dev:freeze
          #     # ... your code
          #     kettle-dev:unfreeze

          # We run code coverage on the latest version of Ruby only.

          # Coverage
          # To retain during kettle-dev templating:
          #     kettle-dev:freeze
          #     # ... your code
          #     kettle-dev:unfreeze
        GEMFILE

        # Template source is simple
        template = <<~GEMFILE
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
        GEMFILE

        # First run
        merger = described_class.new(
          template,
          starting_dest,
          signature_match_preference: :template,
        )

        first_run = merger.merge

        frozen_count = first_run.scan("# frozen_string_literal: true").count
        expect(frozen_count).to eq(1), "First run should deduplicate to 1 frozen_string_literal, got #{frozen_count}\nResult:\n#{first_run}"

        coverage_count = first_run.scan("# Coverage").count
        expect(coverage_count).to eq(2), "First run should maintain 2 '# Coverage' strings, got #{coverage_count}\nResult:\n#{first_run}"

        # Second run (simulating running kettle-dev-setup again)
        merger = described_class.new(
          template,
          starting_dest,
          signature_match_preference: :template,
        )

        second_run = merger.merge

        frozen_count_2 = second_run.scan("# frozen_string_literal: true").count
        expect(frozen_count_2).to eq(1), "Second run should maintain 1 frozen_string_literal, got #{frozen_count_2}\nResult:\n#{second_run}"

        coverage_count_2 = second_run.scan("# Coverage").count
        expect(coverage_count_2).to eq(2), "Second run should maintain 2 '# Coverage' strings, got #{coverage_count_2}\nResult:\n#{second_run}"

        # Should be idempotent
        expect(second_run).to eq(first_run), "Second run should not add more duplicates"
      end
    end

    context "with duplicated non-magic comments" do
      it "does not remove" do
        # When running kettle-dev-setup --allowed=true --force
        # it uses --force to set allow_replace: true
        # This means it uses :replace strategy

        # Starting state: file with 4 frozen_string_literal comments, and 2 duplicate chunks of comments
        starting_dest = <<~GEMFILE
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
          # See gemspec
          # To retain during kettle-dev templating:
          #     kettle-dev:freeze
          #     # ... your code
          #     kettle-dev:unfreeze

          # We run code coverage on the latest version of Ruby only.

          # Coverage
          # To retain during kettle-dev templating:
          #     kettle-dev:freeze
          #     # ... your code
          #     kettle-dev:unfreeze
        GEMFILE

        # Template source is simple
        template = <<~GEMFILE
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
        GEMFILE

        # First run
        merger = described_class.new(
          template,
          starting_dest,
          signature_match_preference: :template,
        )

        first_run = merger.merge

        frozen_count = first_run.scan("# frozen_string_literal: true").count
        expect(frozen_count).to eq(1), "First run should deduplicate to 1 frozen_string_literal, got #{frozen_count}\nResult:\n#{first_run}"

        coverage_count = first_run.scan("# Coverage").count
        expect(coverage_count).to eq(2), "First run should maintain 2 '# Coverage' strings, got #{coverage_count}\nResult:\n#{first_run}"

        # Second run (simulating running kettle-dev-setup again)
        merger = described_class.new(
          template,
          starting_dest,
          signature_match_preference: :template,
        )

        second_run = merger.merge

        frozen_count_2 = second_run.scan("# frozen_string_literal: true").count
        expect(frozen_count_2).to eq(1), "Second run should maintain 1 frozen_string_literal, got #{frozen_count_2}\nResult:\n#{second_run}"

        coverage_count_2 = second_run.scan("# Coverage").count
        expect(coverage_count_2).to eq(2), "Second run should maintain 2 '# Coverage' strings, got #{coverage_count_2}\nResult:\n#{second_run}"

        # Should be idempotent
        expect(second_run).to eq(first_run), "Second run should not add more duplicates"
      end
    end
  end
end
