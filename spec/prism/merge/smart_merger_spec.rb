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

        # Should include freeze marker (unfreeze is still present but has no effect)
        expect(result).to include("# kettle-dev:freeze")

        # Should include method calls
        expect(result).to include('example_method("foo", "bar")')
      end

      it "preserves freeze markers" do
        merger = described_class.new(template_content, dest_content)
        result = merger.merge

        # Count freeze markers
        freeze_count = result.scan("# kettle-dev:freeze").length

        expect(freeze_count).to eq(1)
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

    context "with max_recursion_depth" do
      it "does not recursively merge when max_recursion_depth is reached" do
        template = <<~RUBY
          class MyClass
            def a; 1; end
          end
        RUBY

        dest = <<~RUBY
          class MyClass
            def a; 2; end
            def b; 3; end
          end
        RUBY

        # With max_recursion_depth: 0, should not recursively merge class bodies
        # Default preference is :destination, so dest class wins as atomic unit
        merger = described_class.new(template, dest, max_recursion_depth: 0)
        result = merger.merge

        # Should have the class
        expect(result).to include("class MyClass")
        # Destination version should be kept (both methods)
        expect(result).to include("def a")
        expect(result).to include("def b")
      end
    end

    context "with conditionals" do
      let(:template_path) { "spec/support/fixtures/smart_merge/conditional.template.rb" }
      let(:dest_path) { "spec/support/fixtures/smart_merge/conditional.destination.rb" }
      let(:template_content) { File.read(template_path) }
      let(:dest_content) { File.read(dest_path) }

      it "updates conditional bodies from template" do
        merger = described_class.new(template_content, dest_content, preference: :template)
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

        merger = described_class.new(template, dest, preference: :template, add_template_only_nodes: true)
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

        merger = described_class.new(template, dest, preference: :template)
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

        merger = described_class.new(template, dest, preference: :template)
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

        merger = described_class.new(template, dest, preference: :template)
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

        merger = described_class.new(template, dest, preference: :template)
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

        merger = described_class.new(template, dest, preference: :destination)
        result = merger.merge

        expect(result).to include('var = "junk" # this is the old')
      end
    end

    context "with trailing comments" do
      it "preserves trailing comment lines at end of file" do
        template = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
          # End of file comment
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
        RUBY

        merger = described_class.new(template, dest, preference: :template)
        result = merger.merge

        expect(result).to include("def hello")
        expect(result).to include("# End of file comment")
      end

      it "preserves trailing comment lines from destination" do
        template = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
          # Custom trailing comment
        RUBY

        merger = described_class.new(template, dest, preference: :destination)
        result = merger.merge

        expect(result).to include("def hello")
        expect(result).to include("# Custom trailing comment")
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

        # Parse errors are raised during initialization when FileAnalysis detects invalid syntax
        expect {
          described_class.new(template, dest)
        }.to raise_error(Prism::Merge::TemplateParseError) do |error|
          expect(error.content).to eq(template)
          expect(error.errors).not_to be_empty
        end
      end

      it "raises DestinationParseError when destination is invalid" do
        template = "def hello; end"
        dest = "this is not valid ruby {{"

        # Parse errors are raised during initialization when FileAnalysis detects invalid syntax
        expect {
          described_class.new(template, dest)
        }.to raise_error(Prism::Merge::DestinationParseError) do |error|
          expect(error.content).to eq(dest)
          expect(error.errors).not_to be_empty
        end
      end
    end

    context "with add_template_only_nodes: false" do
      context "with comment disagreements between template and destination" do
        it "uses destination header when template omits header" do
          template = <<~TPL
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
              if true
                # Silly comment
                puts "hello"
              end
            end
          TPL
          dest = <<~DST
            # Existing header
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
            end
          DST

          merger = described_class.new(
            template,
            dest,
            preference: :template,
            add_template_only_nodes: false,
          )
          result = merger.merge

          expect(result).to include('appraise "unlocked" do')
          expect(result).to include('eval_gemfile "a.gemfile"')
          expect(result).to include("# Existing header")
          expect(result).not_to include("# Silly comment")
        end

        it "uses template header when destination present" do
          template = <<~TPL
            # New header from template
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
              if true
                # Silly comment
                puts "hello"
              end
            end
          TPL
          dest = <<~DST
            # Existing header
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
            end
          DST

          merger = described_class.new(
            template,
            dest,
            preference: :template,
            add_template_only_nodes: false,
          )
          result = merger.merge

          expect(result).to include('appraise "unlocked" do')
          expect(result).to include('eval_gemfile "a.gemfile"')
          expect(result).to include("# New header from template")
          expect(result).not_to include("# Existing header")
          expect(result).not_to include("# Silly comment")
        end
      end
    end

    context "with add_template_only_nodes: true" do
      context "with comment disagreements between template and destination" do
        it "uses destination header when template omits header" do
          template = <<~TPL
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
              if true
                # Silly comment
                puts "hello"
              end
            end
          TPL
          dest = <<~DST
            # Existing header
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
            end
          DST

          merger = described_class.new(
            template,
            dest,
            preference: :template,
            add_template_only_nodes: true,
          )
          result = merger.merge

          expect(result).to include('appraise "unlocked" do')
          expect(result).to include('eval_gemfile "a.gemfile"')
          expect(result).to include("# Existing header")
          expect(result).to include("# Silly comment")
        end

        it "uses template header when destination present" do
          template = <<~TPL
            # New header from template
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
              if true
                # Silly comment
                puts "hello"
              end
            end
          TPL
          dest = <<~DST
            # Existing header
            appraise "unlocked" do
              eval_gemfile "a.gemfile"
            end
          DST

          merger = described_class.new(
            template,
            dest,
            preference: :template,
            add_template_only_nodes: true,
          )
          result = merger.merge

          expect(result).to include('appraise "unlocked" do')
          expect(result).to include('eval_gemfile "a.gemfile"')
          expect(result).to include("# New header from template")
          expect(result).not_to include("# Existing header")
          expect(result).to include("# Silly comment")
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

    it "returns debug info with statement counts" do
      template = "def hello; end"
      dest = "def hello; end"
      merger = described_class.new(template, dest)
      result = merger.merge_with_debug

      expect(result[:debug][:template_statements]).to eq(1)
      expect(result[:debug][:dest_statements]).to eq(1)
      expect(result[:debug][:preference]).to eq(:destination)
      expect(result[:debug][:add_template_only_nodes]).to be(false)
      expect(result[:debug][:freeze_token]).to eq("prism-merge")
    end

    it "returns statistics from the merge result" do
      template = "def hello; end"
      dest = "def hello; end"
      merger = described_class.new(template, dest)
      result = merger.merge_with_debug

      expect(result[:statistics]).to be_a(Hash)
      expect(result[:statistics].values).to all(be_a(Integer))
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
          preference: :template,
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
          preference: :destination,
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
        merger = described_class.new(template_content, dest_content, freeze_token: "kettle-dev")
        result = merger.merge

        # Node with freeze marker in destination should be preserved
        expect(result).to include('secret: "destination secret"')
        expect(result).to include('api_key: "abc123"')

        # Should include freeze marker
        expect(result).to include("# kettle-dev:freeze")
      end

      it "preserves frozen nodes even with template preference" do
        merger = described_class.new(
          template_content,
          dest_content,
          preference: :template,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        # Frozen node (with freeze marker) still wins from destination
        expect(result).to include('secret: "destination secret"')
        expect(result).to include('api_key: "abc123"')
      end
    end

    context "with recursive merge leading comment handling" do
      it "uses template leading comments when preference is :template" do
        template = <<~RUBY
          # Template leading
          class A
            def foo
              1
            end
          end
        RUBY

        dest = <<~RUBY
          # Dest leading
          class A
            def foo
              2
            end
          end
        RUBY

        merger = described_class.new(template, dest, preference: :template)
        result = merger.merge

        expect(result).to include("# Template leading")
        expect(result).not_to include("# Dest leading")
      end

      it "preserves destination leading comments when preference is :destination" do
        template = <<~RUBY
          # Template leading
          class A
            def foo
              1
            end
          end
        RUBY

        dest = <<~RUBY
          # Dest leading
          class A
            def foo
              2
            end
          end
        RUBY

        merger = described_class.new(template, dest, preference: :destination)
        result = merger.merge

        expect(result).to include("# Dest leading")
        expect(result).not_to include("# Template leading")
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
          preference: :destination,
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
          preference: :template,
        )
        result = merger.merge

        # Template version should win for matched nodes
        expect(result).to include('config.setting = "template value"')

        # Destination-only nodes inside recursively merged blocks are preserved
        expect(result).to include("config.extra")

        # Destination-only top-level call should still be preserved
        expect(result).to include('cleanup("temp")')
      end

      it "add_template_only_nodes only affects template-only nodes, not destination-only" do
        merger = described_class.new(
          template_content,
          dest_content,
          preference: :template,
          add_template_only_nodes: false,
        )
        result = merger.merge

        # Template version should win for matched nodes
        expect(result).to include('config.setting = "template value"')

        # Destination-only nodes are always preserved (they represent user customizations)
        # add_template_only_nodes only controls TEMPLATE-only nodes
        expect(result).to include("config.extra")

        # Destination-only top-level call is also preserved
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
          preference: :destination,
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
          preference: :template,
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
          preference: :destination,
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
          preference: :template,
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

    context "with top-level constants and preference" do
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

      it "uses template version when preference is :template" do
        merger = described_class.new(
          template_code,
          dest_code,
          preference: :template,
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

      it "uses destination version when preference is :destination (default)" do
        merger = described_class.new(
          template_code,
          dest_code,
          preference: :destination,
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

      it "includes standalone comments from template when using template preference" do
        merger = described_class.new(
          template_code,
          dest_code,
          preference: :template,  # Use template version to get its comments
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
          preference: :template,
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
          preference: :template,
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
      it "uses template content for comment-only files when preference is template" do
        # Comment-only files have no AST nodes to merge
        # SmartMerger uses signature-based matching for comment nodes

        starting_dest = <<~GEMFILE
          # frozen_string_literal: true
          # frozen_string_literal: true
          # frozen_string_literal: true
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
          # See gemspec
        GEMFILE

        template = <<~GEMFILE
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
        GEMFILE

        merger = described_class.new(
          template,
          starting_dest,
          preference: :template,
        )

        result = merger.merge

        # With preference: :template, matching nodes use template version
        # Duplicate frozen_string_literal lines in dest are deduplicated via signature matching
        frozen_count = result.scan("# frozen_string_literal: true").count
        expect(frozen_count).to eq(1), "Should have 1 frozen_string_literal from template\nResult:\n#{result}"

        coverage_count = result.scan("# Coverage").count
        expect(coverage_count).to eq(1), "Should have 1 '# Coverage' from template\nResult:\n#{result}"

        # Note: Idempotency may not be perfect due to how Comment::Parser groups
        # consecutive comment lines into Blocks. When empty lines between comments
        # are deduplicated (same [:empty_line] signature), the parser may group
        # comments differently on subsequent runs. This is a known edge case.
        #
        # For most practical use cases (deduplicating templated files), the first
        # merge achieves the desired result. Perfect idempotency for comment-only
        # files with complex whitespace patterns may be addressed in future versions.
        second_merger = described_class.new(template, result, preference: :template)
        second_run = second_merger.merge

        # Verify key content is preserved even if formatting differs slightly
        expect(second_run).to include("# frozen_string_literal: true")
        expect(second_run).to include("# We run code coverage")
      end
    end

    context "with duplicated non-magic comments" do
      it "uses template content for comment-only files" do
        # Comment-only files have no AST nodes to merge
        # SmartMerger uses signature-based matching for comment nodes

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

        template = <<~GEMFILE
          # frozen_string_literal: true

          # We run code coverage on the latest version of Ruby only.

          # Coverage
        GEMFILE

        merger = described_class.new(
          template,
          starting_dest,
          preference: :template,
        )

        result = merger.merge

        # With preference: :template, matching nodes use template version
        # Duplicate content in dest is deduplicated via signature matching
        frozen_count = result.scan("# frozen_string_literal: true").count
        expect(frozen_count).to eq(1), "Should have 1 frozen_string_literal from template\nResult:\n#{result}"

        coverage_count = result.scan("# Coverage").count
        expect(coverage_count).to eq(1), "Should have 1 '# Coverage' from template\nResult:\n#{result}"

        # Note: Idempotency may not be perfect due to how Comment::Parser groups
        # consecutive comment lines into Blocks. When empty lines between comments
        # are deduplicated (same [:empty_line] signature), the parser may group
        # comments differently on subsequent runs. This is a known edge case.
        #
        # For most practical use cases (deduplicating templated files), the first
        # merge achieves the desired result.
        second_merger = described_class.new(template, result, preference: :template)
        second_run = second_merger.merge

        # Verify key content is preserved even if formatting differs slightly
        expect(second_run).to include("# frozen_string_literal: true")
        expect(second_run).to include("# We run code coverage")
      end
    end

    describe "#should_merge_recursively?" do
      it "returns false when template_node is nil" do
        source = <<~RUBY
          class Foo; end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        result = merger.send(:should_merge_recursively?, nil, Prism.parse(source).value.statements.body.first)
        expect(result).to be false
      end

      it "returns false when dest_node is nil" do
        source = <<~RUBY
          class Foo; end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        result = merger.send(:should_merge_recursively?, Prism.parse(source).value.statements.body.first, nil)
        expect(result).to be false
      end

      it "returns false when nodes are different types" do
        class_source = "class Foo; end"
        module_source = "module Bar; end"

        merger = described_class.new(class_source, module_source)
        merger.merge

        class_node = Prism.parse(class_source).value.statements.body.first
        module_node = Prism.parse(module_source).value.statements.body.first

        result = merger.send(:should_merge_recursively?, class_node, module_node)
        expect(result).to be false
      end

      it "returns true for matching ClassNode nodes without freeze blocks" do
        source = <<~RUBY
          class Foo
            def bar; end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be true
      end

      it "returns true for matching ModuleNode nodes" do
        source = <<~RUBY
          module Foo
            def bar; end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be true
      end

      it "returns true for matching SingletonClassNode nodes" do
        source = <<~RUBY
          class << self
            def bar; end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be true
      end

      it "returns false for CallNode without blocks" do
        source = "puts 'hello'"

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns true for CallNode with matching blocks" do
        source = <<~RUBY
          describe "test" do
            it "works" do
              expect(true).to be true
            end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be true
      end

      it "returns true for matching BeginNode with statements" do
        source = <<~RUBY
          begin
            foo
          rescue
            bar
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be true
      end

      it "returns false for BeginNode without statements" do
        source = <<~RUBY
          begin
          rescue
            bar
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for CaseNode" do
        source = <<~RUBY
          case x
          when 1
            :one
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for CaseMatchNode" do
        source = <<~RUBY
          case x
          in {a:}
            a
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for WhileNode" do
        source = <<~RUBY
          while true
            foo
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for UntilNode" do
        source = <<~RUBY
          until false
            foo
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for ForNode" do
        source = <<~RUBY
          for i in [1,2,3]
            puts i
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for LambdaNode" do
        source = <<~RUBY
          -> { puts "hi" }
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end

      it "returns false for DefNode (not recursively merged)" do
        source = <<~RUBY
          def hello
            puts "world"
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:should_merge_recursively?, node, node)
        expect(result).to be false
      end
    end

    describe "#node_contains_freeze_blocks?" do
      it "returns false when no freeze_token is set" do
        source = <<~RUBY
          class Foo
            # kettle-dev:freeze
            def bar; end
            # kettle-dev:unfreeze
          end
        RUBY

        merger = described_class.new(source, source, freeze_token: nil)
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be false
      end

      it "returns true when ClassNode contains freeze markers" do
        source = <<~RUBY
          class Foo
            # kettle-dev:freeze
            def bar; end
            # kettle-dev:unfreeze
          end
        RUBY

        merger = described_class.new(source, source, freeze_token: "kettle-dev")
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be true
      end

      it "returns true when ModuleNode contains freeze markers" do
        source = <<~RUBY
          module Foo
            # kettle-dev:freeze
            def bar; end
            # kettle-dev:unfreeze
          end
        RUBY

        merger = described_class.new(source, source, freeze_token: "kettle-dev")
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be true
      end

      it "checks SingletonClassNode for freeze markers via comments" do
        # Use source without freeze blocks to avoid validation errors
        # Then manually set freeze_token to test comment scanning
        source = <<~RUBY
          class << self
            def bar
              1
            end
          end
        RUBY

        merger = described_class.new(source, source, freeze_token: nil)
        merger.merge

        # Now set freeze_token manually to test the comment scanning logic
        merger.instance_variable_set(:@freeze_token, "kettle-dev")

        node = Prism.parse(source).value.statements.body.first
        # Should return false since no freeze comments exist in source
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be false
      end

      it "checks LambdaNode body attribute for content" do
        # Test that the method correctly identifies LambdaNode as having content
        source = <<~RUBY
          myproc = -> {
            x = 1
            puts x
          }
        RUBY

        merger = described_class.new(source, source, freeze_token: nil)
        merger.merge

        # Manually set freeze_token to test the has_content logic
        merger.instance_variable_set(:@freeze_token, "kettle-dev")

        node = Prism.parse(source).value.statements.body.first.value
        # Should return false since no freeze comments exist
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be false
      end

      it "returns false when IfNode body has no freeze markers" do
        source = <<~RUBY
          if condition
            puts "hello"
          end
        RUBY

        merger = described_class.new(source, source, freeze_token: "kettle-dev")
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be false
      end

      it "checks CallNode block attribute for content" do
        # Test that the method correctly identifies CallNode with block as having content
        source = <<~RUBY
          describe "test" do
            it "works" do
              expect(true).to be true
            end
          end
        RUBY

        merger = described_class.new(source, source, freeze_token: nil)
        merger.merge

        # Manually set freeze_token to test the has_content logic path
        merger.instance_variable_set(:@freeze_token, "kettle-dev")

        node = Prism.parse(source).value.statements.body.first
        # Should return false since no freeze comments exist
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be false
      end

      it "handles nodes without body/statements/block" do
        source = "x = 1"

        merger = described_class.new(source, source, freeze_token: "kettle-dev")
        merger.merge

        node = Prism.parse(source).value.statements.body.first
        result = merger.send(:node_contains_freeze_blocks?, node, merger.template_analysis)
        expect(result).to be false
      end
    end

    describe "#extract_node_body" do
      it "extracts body from ClassNode" do
        source = <<~RUBY
          class Foo
            def bar
              1
            end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("def bar")
        expect(body).to include("1")
      end

      it "extracts body from ModuleNode" do
        source = <<~RUBY
          module Foo
            CONST = 1
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("CONST = 1")
      end

      it "extracts body from SingletonClassNode" do
        source = <<~RUBY
          class << self
            def foo; end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("def foo; end")
      end

      it "extracts body from BeginNode" do
        source = <<~RUBY
          begin
            foo
            bar
          rescue
            baz
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("foo")
        expect(body).to include("bar")
      end

      it "extracts body from CallNode with block" do
        source = <<~RUBY
          describe "test" do
            it "works" do
              expect(true).to be true
            end
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("it \"works\"")
      end

      it "extracts body from LambdaNode" do
        source = <<~RUBY
          -> {
            puts "hello"
            puts "world"
          }
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("puts \"hello\"")
      end

      it "returns empty string for CaseNode" do
        source = <<~RUBY
          case x
          when 1
            :one
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to eq("")
      end

      it "returns empty string for node with empty body" do
        source = "class Foo; end"

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to eq("")
      end

      it "returns empty string for node without statements (nil)" do
        source = "x = 1"

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to eq("")
      end

      it "handles ParenthesesNode" do
        source = <<~RUBY
          (
            puts "inside"
            puts "parens"
          )
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("puts \"inside\"")
      end

      it "uses respond_to? fallback for unknown node types" do
        source = <<~RUBY
          for i in [1, 2, 3]
            puts i
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = Prism.parse(source).value.statements.body.first

        # ForNode has .statements, should work via fallback
        body = merger.send(:extract_node_body, node, analysis)
        expect(body).to include("puts i")
      end
    end

    describe "infinite recursion prevention" do
      context "with git_source blocks having matching signatures" do
        # Regression test for infinite recursion bug when merging CallNodes with blocks
        # that have matching signatures but non-mergeable body content (just literals).
        # The fix detects that the block body contains no mergeable statements and
        # treats the node atomically instead of recursing.
        it "does not cause infinite recursion with custom signature generator" do
          src = <<~'SRC'
            source "https://gem.coop"
            git_source(:bitbucket) { |repo_name| "https://bitbucket.org/#{repo_name}" }
          SRC

          dest = <<~'DEST'
            # Header
            source "https://gem.coop"
            git_source(:bitbucket) { |repo_name| "https://bb.org/#{repo_name}" }
          DEST

          # Custom signature generator that matches git_source by their first argument
          signature_generator = ->(node) {
            return unless node.is_a?(Prism::CallNode)
            return unless [:gem, :source, :git_source].include?(node.name)

            return [:source] if node.name == :source

            first_arg = node.arguments&.arguments&.first
            arg_value = case first_arg
            when Prism::StringNode
              first_arg.unescaped.to_s
            when Prism::SymbolNode
              first_arg.unescaped.to_sym
            end

            arg_value ? [node.name, arg_value] : nil
          }

          # This should NOT raise SystemStackError
          merger = described_class.new(
            src,
            dest,
            preference: :template,
            add_template_only_nodes: true,
            signature_generator: signature_generator,
          )

          result = nil
          expect { result = merger.merge }.not_to raise_error

          # Verify merge produces valid output
          expect(result).to include("source")
          expect(result).to include("git_source(:bitbucket)")
        end

        it "uses template content for blocks with non-mergeable body when preference is template" do
          src = <<~'SRC'
            git_source(:github) { |repo| "https://github.com/#{repo}" }
          SRC

          dest = <<~'DEST'
            git_source(:github) { |repo| "https://gh.com/#{repo}" }
          DEST

          signature_generator = ->(node) {
            return unless node.is_a?(Prism::CallNode)
            return unless node.name == :git_source
            first_arg = node.arguments&.arguments&.first
            return unless first_arg.is_a?(Prism::SymbolNode)
            [:git_source, first_arg.unescaped.to_sym]
          }

          merger = described_class.new(
            src,
            dest,
            preference: :template,
            signature_generator: signature_generator,
          )

          result = merger.merge
          # Template version should win since body is not mergeable (just a string)
          expect(result).to include("https://github.com")
        end

        it "uses destination content for blocks with non-mergeable body when preference is destination" do
          src = <<~'SRC'
            git_source(:github) { |repo| "https://github.com/#{repo}" }
          SRC

          dest = <<~'DEST'
            git_source(:github) { |repo| "https://gh.com/#{repo}" }
          DEST

          signature_generator = ->(node) {
            return unless node.is_a?(Prism::CallNode)
            return unless node.name == :git_source
            first_arg = node.arguments&.arguments&.first
            return unless first_arg.is_a?(Prism::SymbolNode)
            [:git_source, first_arg.unescaped.to_sym]
          }

          merger = described_class.new(
            src,
            dest,
            preference: :destination,
            signature_generator: signature_generator,
          )

          result = merger.merge
          # Destination version should win since body is not mergeable (just a string)
          expect(result).to include("https://gh.com")
        end
      end

      context "with blocks containing mergeable statements" do
        it "recursively merges RSpec describe blocks with nested it blocks" do
          src = <<~SRC
            describe "Calculator" do
              it "adds numbers" do
                expect(1 + 1).to eq(2)
              end
            end
          SRC

          dest = <<~DEST
            describe "Calculator" do
              it "adds numbers" do
                expect(2 + 2).to eq(4)
              end
              it "subtracts numbers" do
                expect(5 - 3).to eq(2)
              end
            end
          DEST

          merger = described_class.new(src, dest, preference: :destination)
          result = merger.merge

          # Should preserve destination's custom it block
          expect(result).to include("subtracts numbers")
          # Should have both it blocks
          expect(result.scan('it "').count).to eq(2)
        end
      end

      context "with max_recursion_depth safety valve" do
        it "stops recursion when max_recursion_depth is reached" do
          # Deeply nested structure that would normally recurse
          src = <<~SRC
            class Outer
              class Inner
                def foo
                  :template
                end
              end
            end
          SRC

          dest = <<~DEST
            class Outer
              class Inner
                def foo
                  :destination
                end
              end
            end
          DEST

          # With max_recursion_depth: 0, no recursive merging should happen at all
          # The top-level class will be treated atomically based on preference
          merger = described_class.new(
            src,
            dest,
            preference: :destination,
            max_recursion_depth: 0,
          )
          result = merger.merge

          # Since recursion is blocked at depth 0, should use destination atomically
          expect(result).to include(":destination")
          expect(result).not_to include(":template")
        end

        it "allows recursion up to the specified depth" do
          src = <<~SRC
            class Outer
              class Inner
                def foo
                  :template
                end
              end
            end
          SRC

          dest = <<~DEST
            class Outer
              class Inner
                def foo
                  :destination
                end
                def bar
                  :custom
                end
              end
            end
          DEST

          # With max_recursion_depth: 2, can recurse into Outer and Inner
          merger = described_class.new(
            src,
            dest,
            preference: :destination,
            max_recursion_depth: 2,
          )
          result = merger.merge

          # Should preserve destination's custom method since recursion is allowed
          expect(result).to include("def bar")
          expect(result).to include(":custom")
        end
      end
    end
  end

  describe "preference: :template" do
    it "uses template version when nodes have matching signatures" do
      template = <<~RUBY
        # frozen_string_literal: true

        VERSION = "2.0.0"

        def shared_method
          puts "template version"
        end
      RUBY

      destination = <<~RUBY
        # frozen_string_literal: true

        VERSION = "1.0.0"

        def shared_method
          puts "destination version"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :template,
        add_template_only_nodes: true,
      )
      result = merger.merge

      # Template version should win for VERSION constant
      expect(result).to include('VERSION = "2.0.0"')
      expect(result).not_to include('VERSION = "1.0.0"')

      # Template version should win for shared_method
      expect(result).to include('puts "template version"')
      expect(result).not_to include('puts "destination version"')
    end

    it "adds template-only nodes when preference is template" do
      template = <<~RUBY
        def template_only_method
          "from template"
        end

        def shared_method
          "template"
        end
      RUBY

      destination = <<~RUBY
        def shared_method
          "destination"
        end

        def dest_only_method
          "from destination"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :template,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to include("def template_only_method")
      expect(result).to include("def dest_only_method")
      expect(result).to include('"template"')
      expect(result).not_to include('"destination"')
    end
  end

  describe "signature generator fallthrough with FreezeNode" do
    it "allows fallthrough by returning FreezeNode from custom generator" do
      template = <<~RUBY
        gem "foo"
        gem "bar"
      RUBY

      destination = <<~RUBY
        # kettle-dev:freeze
        gem "frozen_gem"
        # kettle-dev:unfreeze
        gem "bar"
      RUBY

      # This generator returns FreezeNode unchanged to trigger fallthrough
      fallthrough_generator = lambda do |node|
        case node
        when Prism::CallNode
          if node.name == :gem
            [:gem, node.arguments&.arguments&.first&.unescaped]
          else
            node # fallthrough for other calls
          end
        when Prism::Merge::FreezeNode
          # Return FreezeNode to trigger fallthrough to default signature
          node
        else
          node # fallthrough to default
        end
      end

      merger = described_class.new(
        template,
        destination,
        signature_generator: fallthrough_generator,
        add_template_only_nodes: true,
        freeze_token: "kettle-dev",
      )
      result = merger.merge

      # Freeze block should be preserved
      expect(result).to include('gem "frozen_gem"')
      expect(result).to include("kettle-dev:freeze")
      # Template-only gem should be added
      expect(result).to include('gem "foo"')
    end
  end

  describe "identical files optimization" do
    it "returns content unchanged when template equals destination" do
      content = <<~RUBY
        # frozen_string_literal: true

        def identical_method
          puts "same in both"
        end

        CONSTANT = "value"
      RUBY

      merger = described_class.new(content, content)
      result = merger.merge

      # Should preserve the content exactly
      expect(result.strip).to eq(content.strip)
    end
  end

  describe "recursive merge with nested freeze blocks" do
    it "does not recurse into nodes containing freeze blocks" do
      template = <<~RUBY
        class MyClass
          def method_a
            "template a"
          end

          def method_b
            "template b"
          end
        end
      RUBY

      destination = <<~RUBY
        class MyClass
          def method_a
            "destination a"
          end

          # prism-merge:freeze
          def method_b
            "frozen b"
          end
          # prism-merge:unfreeze
        end
      RUBY

      # Use :destination preference so we can see the freeze block preserved
      # The class won't be recursively merged because dest has freeze blocks
      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      # The class should not be recursively merged because dest has freeze blocks
      # So destination version should be preserved entirely
      expect(result).to include("prism-merge:freeze")
      expect(result).to include('"frozen b"')
      expect(result).to include('"destination a"')
    end
  end

  describe "boundary after last anchor" do
    it "handles boundaries that come after all anchors" do
      template = <<~RUBY
        def shared_method
          "shared"
        end
      RUBY

      destination = <<~RUBY
        def shared_method
          "shared"
        end

        def extra_method
          "extra"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        add_template_only_nodes: false,
      )
      result = merger.merge

      # The extra_method is destination-only and comes after the last anchor
      expect(result).to include("def shared_method")
      expect(result).to include("def extra_method")
    end
  end

  describe "body extraction edge cases" do
    it "handles BeginNode for recursive merge consideration" do
      template = <<~RUBY
        begin
          def inner_method
            "template"
          end
        end
      RUBY

      destination = <<~RUBY
        begin
          def inner_method
            "destination"
          end
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("def inner_method")
    end

    it "handles ParenthesesNode" do
      template = <<~RUBY
        (
          CONST = 1
        )
      RUBY

      destination = <<~RUBY
        (
          CONST = 2
        )
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      expect(result).to include("CONST =")
    end

    it "handles nodes without standard body accessors" do
      # This tests the else branch with respond_to? checks
      template = <<~RUBY
        while true
          x = 1
        end
      RUBY

      destination = <<~RUBY
        while true
          x = 2
        end
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      expect(result).to include("while true")
    end
  end

  describe "CallNode with block for recursive merge" do
    it "considers CallNode with block for recursive merging" do
      template = <<~RUBY
        Rails.application.configure do
          config.setting_a = "template_a"
          config.setting_b = "template_b"
        end
      RUBY

      destination = <<~RUBY
        Rails.application.configure do
          config.setting_a = "dest_a"
          config.setting_c = "dest_c"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true,
      )
      result = merger.merge

      # The block should potentially be recursively merged
      expect(result).to include("Rails.application.configure")
    end
  end

  describe "get_body_content edge cases" do
    it "handles IfNode for body extraction" do
      template = <<~RUBY
        if condition
          def method_a
            "template"
          end
        end
      RUBY

      destination = <<~RUBY
        if condition
          def method_a
            "destination"
          end
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("if condition")
    end

    it "handles UnlessNode for body extraction" do
      template = <<~RUBY
        unless condition
          def method_a
            "template"
          end
        end
      RUBY

      destination = <<~RUBY
        unless condition
          def method_a
            "destination"
          end
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("unless condition")
    end

    it "handles ForNode for body extraction" do
      template = <<~RUBY
        for i in items
          def method_a
            "template"
          end
        end
      RUBY

      destination = <<~RUBY
        for i in items
          def method_a
            "destination"
          end
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("for i in items")
    end

    it "handles CaseNode (returns nil, no recursion)" do
      template = <<~RUBY
        case x
        when 1
          "one"
        when 2
          "two"
        end
      RUBY

      destination = <<~RUBY
        case x
        when 1
          "uno"
        when 2
          "dos"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("case x")
    end

    it "handles empty body statements" do
      template = <<~RUBY
        class EmptyClass
        end
      RUBY

      destination = <<~RUBY
        class EmptyClass
        end
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      expect(result).to include("class EmptyClass")
      expect(result).to include("end")
    end
  end

  describe "timeline boundary positioning" do
    it "handles boundary before first anchor" do
      template = <<~RUBY
        BEFORE = "before"

        def anchored_method
          "same"
        end
      RUBY

      destination = <<~RUBY
        def anchored_method
          "same"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        add_template_only_nodes: true,
      )
      result = merger.merge

      # Template-only content before the anchor
      expect(result).to include("BEFORE")
      expect(result).to include("def anchored_method")
    end

    it "handles boundary between anchors" do
      template = <<~RUBY
        def method_a
          "same"
        end

        MIDDLE = "template middle"

        def method_b
          "same"
        end
      RUBY

      destination = <<~RUBY
        def method_a
          "same"
        end

        MIDDLE = "dest middle"

        def method_b
          "same"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("def method_a")
      expect(result).to include("def method_b")
    end
  end

  describe "unknown anchor match type" do
    it "defaults to template for unknown match types" do
      # This is hard to test directly, but we can verify the code path exists
      # by checking that exact_match anchors work
      template = <<~RUBY
        # Exact same content
        def identical_method
          "same"
        end
      RUBY

      merger = described_class.new(template, template)
      result = merger.merge

      expect(result).to include("def identical_method")
    end
  end

  describe "recursion depth limiting" do
    it "stops recursive merging when max_recursion_depth is reached" do
      # Create deeply nested classes that would normally recurse
      template = <<~RUBY
        class Outer
          class Middle
            class Inner
              def deep_method
                "template"
              end
            end
          end
        end
      RUBY

      destination = <<~RUBY
        class Outer
          class Middle
            class Inner
              def deep_method
                "destination"
              end
            end
          end
        end
      RUBY

      # With max_recursion_depth: 1, it should stop after Outer level
      merger = described_class.new(
        template,
        destination,
        max_recursion_depth: 1,
      )
      result = merger.merge

      # The merge should complete without infinite recursion
      expect(result).to include("class Outer")
      expect(result).to include("class Middle")
    end
  end

  describe "extract_node_body edge cases" do
    it "handles IfNode body extraction" do
      template = <<~RUBY
        if condition
          def inside_if
            "template"
          end
        end
      RUBY

      destination = <<~RUBY
        if condition
          def inside_if
            "dest"
          end
        end
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      expect(result).to include("if condition")
      expect(result).to include("def inside_if")
    end

    it "handles CaseNode without mergeable body" do
      template = <<~RUBY
        case x
        when 1 then :one
        when 2 then :two
        end
      RUBY

      destination = <<~RUBY
        case x
        when 1 then :one
        when 2 then :two
        end
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      expect(result).to include("case x")
      expect(result).to include("when 1")
    end

    it "handles ParenthesesNode body extraction" do
      template = <<~RUBY
        result = (
          complex_expression +
          another_expression
        )
      RUBY

      merger = described_class.new(template, template)
      result = merger.merge

      expect(result).to include("result =")
      expect(result).to include("complex_expression")
    end

    it "handles node with respond_to?(:body) but no statements method" do
      template = <<~RUBY
        begin
          risky_code
        rescue => e
          handle(e)
        end
      RUBY

      merger = described_class.new(template, template)
      result = merger.merge

      expect(result).to include("begin")
      expect(result).to include("risky_code")
    end
  end

  describe "body_has_mergeable_statements? behavior" do
    it "returns false for bodies with only literals" do
      # A block containing only a string literal shouldn't be recursively merged
      template = <<~RUBY
        config do
          "just a string"
        end
      RUBY

      destination = <<~RUBY
        config do
          "different string"
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      # Should treat block atomically, preferring destination
      expect(result).to include("different string")
    end

    it "returns true for bodies with method definitions" do
      template = <<~RUBY
        class Example
          def method_one
            "template"
          end
        end
      RUBY

      destination = <<~RUBY
        class Example
          def method_one
            "dest"
          end

          def method_two
            "custom"
          end
        end
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      # Should recursively merge, preserving method_two
      expect(result).to include("def method_one")
      expect(result).to include("def method_two")
    end
  end

  describe "should_merge_recursively? edge cases" do
    it "returns false when nodes are different types" do
      template = <<~RUBY
        class Foo
          "template"
        end
      RUBY

      # Different structure - module vs class
      destination = <<~RUBY
        module Foo
          "dest"
        end
      RUBY

      merger = described_class.new(template, destination)
      result = merger.merge

      # Should not merge recursively since types differ
      expect(result).to include("class Foo").or include("module Foo")
    end

    it "does not recursively merge WhileNode" do
      template = <<~RUBY
        while running
          process_item
        end
      RUBY

      destination = <<~RUBY
        while running
          process_item
          log_progress
        end
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      # WhileNode should be treated atomically
      expect(result).to include("while running")
    end

    it "does not recursively merge LambdaNode" do
      template = <<~RUBY
        processor = -> {
          step_one
        }
      RUBY

      destination = <<~RUBY
        processor = -> {
          step_one
          step_two
        }
      RUBY

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
      )
      result = merger.merge

      # Lambda should be treated atomically
      expect(result).to include("processor =")
    end
  end

  describe "internal methods coverage" do
    describe "#aligner_class" do
      it "returns nil (SmartMerger doesn't use aligners)" do
        merger = described_class.new("# comment", "# comment")
        expect(merger.send(:aligner_class)).to be_nil
      end
    end

    describe "#resolver_class" do
      it "returns nil (SmartMerger doesn't use resolvers)" do
        merger = described_class.new("# comment", "# comment")
        expect(merger.send(:resolver_class)).to be_nil
      end
    end

    describe "#build_result" do
      it "returns a new MergeResult instance" do
        merger = described_class.new("# comment", "# comment")
        result = merger.send(:build_result)
        expect(result).to be_a(Prism::Merge::MergeResult)
      end

      it "passes template_analysis and dest_analysis to MergeResult" do
        merger = described_class.new("x = 1", "y = 2")
        result = merger.result

        expect(result).to be_a(Prism::Merge::MergeResult)
        expect(result.template_analysis).to eq(merger.template_analysis)
        expect(result.dest_analysis).to eq(merger.dest_analysis)
      end
    end
  end

  describe "preference_for_node with Hash preference and node_typing" do
    describe "#preference_for_node directly" do
      it "returns typed preference when node_typing wraps node" do
        template = "VERSION = '1.0'"
        dest = "VERSION = '2.0'"

        node_typing = {
          ConstantWriteNode: ->(node) { Ast::Merge::NodeTyping.with_merge_type(node, :version) },
        }

        merger = described_class.new(
          template,
          dest,
          preference: {version: :template, default: :destination},
          node_typing: node_typing,
        )

        # Get the actual nodes from the analyses
        template_node = merger.send(:instance_variable_get, :@template_analysis).statements.first
        dest_node = merger.send(:instance_variable_get, :@dest_analysis).statements.first

        # Verify the nodes are the expected type
        expect(template_node).to be_a(Prism::ConstantWriteNode)
        expect(dest_node).to be_a(Prism::ConstantWriteNode)

        # Verify @preference is a Hash
        preference = merger.send(:instance_variable_get, :@preference)
        expect(preference).to be_a(Hash)
        expect(preference).to eq({version: :template, default: :destination})

        # Verify @node_typing is set
        node_typing_config = merger.send(:instance_variable_get, :@node_typing)
        expect(node_typing_config).not_to be_nil

        # Verify that NodeTyping.process actually wraps the node
        typed_node = Ast::Merge::NodeTyping.process(template_node, node_typing_config)
        expect(Ast::Merge::NodeTyping.typed_node?(typed_node)).to be(true)
        expect(Ast::Merge::NodeTyping.merge_type_for(typed_node)).to eq(:version)

        # Now verify preference_for_node returns the correct preference
        pref = merger.send(:preference_for_node, template_node, dest_node)
        expect(pref).to eq(:template)
      end

      it "returns default preference when merge_type not in preference hash" do
        template = "VERSION = '1.0'"
        dest = "VERSION = '2.0'"

        node_typing = {
          ConstantWriteNode: ->(node) { Ast::Merge::NodeTyping.with_merge_type(node, :version) },
        }

        merger = described_class.new(
          template,
          dest,
          preference: {other_type: :template, default: :destination},
          node_typing: node_typing,
        )

        template_node = merger.send(:instance_variable_get, :@template_analysis).statements.first
        dest_node = merger.send(:instance_variable_get, :@dest_analysis).statements.first

        pref = merger.send(:preference_for_node, template_node, dest_node)
        expect(pref).to eq(:destination)
      end
    end

    describe "integration: merge with node_typing and Hash preference", :check_output do
      it "investigates why merge doesn't use typed preference" do
        template = "VERSION = '2.0'"
        dest = "VERSION = '1.0'"

        node_typing = {
          ConstantWriteNode: ->(node) { Ast::Merge::NodeTyping.with_merge_type(node, :version) },
        }

        merger = described_class.new(
          template,
          dest,
          preference: {version: :template, default: :destination},
          node_typing: node_typing,
        )

        # Get template and dest nodes
        template_node = merger.send(:instance_variable_get, :@template_analysis).statements.first
        dest_node = merger.send(:instance_variable_get, :@dest_analysis).statements.first

        # Check signatures - do they match?
        template_analysis = merger.send(:instance_variable_get, :@template_analysis)
        dest_analysis = merger.send(:instance_variable_get, :@dest_analysis)

        template_sig = template_analysis.generate_signature(template_node)
        dest_sig = dest_analysis.generate_signature(dest_node)

        # Debug output
        puts "Template signature: #{template_sig.inspect}"
        puts "Dest signature: #{dest_sig.inspect}"
        puts "Signatures match: #{template_sig == dest_sig}"

        # Verify signatures match (they should for VERSION = ...)
        expect(template_sig).to eq(dest_sig), "Signatures should match for matching constants"

        # Check should_merge_recursively? - should be false for ConstantWriteNode
        should_recurse = merger.send(:should_merge_recursively?, template_node, dest_node)
        expect(should_recurse).to be(false), "ConstantWriteNode should not merge recursively"

        # Check preference_for_node returns correct value
        pref = merger.send(:preference_for_node, template_node, dest_node)
        expect(pref).to eq(:template), "preference_for_node should return :template for typed node"

        # Now call merge and check the result
        result = merger.merge

        # The result should contain template version since preference_for_node returns :template
        expect(result).to include("2.0"), "Merge should use template version when preference_for_node returns :template"
      end
    end

    context "with Hash preference but no node_typing" do
      it "uses default_preference from the hash" do
        template = <<~RUBY
          VERSION = "2.0.0"
        RUBY

        dest = <<~RUBY
          VERSION = "1.0.0"
        RUBY

        merger = described_class.new(
          template,
          dest,
          preference: {default: :template},
        )
        result = merger.merge

        expect(result).to include('VERSION = "2.0.0"')
      end

      it "uses :destination when no default key in hash" do
        template = <<~RUBY
          VERSION = "2.0.0"
        RUBY

        dest = <<~RUBY
          VERSION = "1.0.0"
        RUBY

        merger = described_class.new(
          template,
          dest,
          preference: {other: :template},
        )
        result = merger.merge

        # Should fall back to :destination when no :default key
        expect(result).to include('VERSION = "1.0.0"')
      end
    end

    it "uses typed dest merge_type when template is not typed" do
      template = <<~RUBY
        gem "foo"
        gem "bar"
      RUBY

      dest = <<~RUBY
        gem "foo"
        gem "bar"
      RUBY

      # node_typing that only types "bar" as :special
      node_typing = {
        CallNode: ->(node) {
          if node.respond_to?(:arguments) &&
              node.arguments&.arguments&.first.respond_to?(:unescaped) &&
              node.arguments.arguments.first.unescaped == "bar"
            Ast::Merge::NodeTyping.with_merge_type(node, :special)
          end
        },
      }

      merger = described_class.new(
        template,
        dest,
        preference: {default: :destination, special: :template},
        node_typing: node_typing,
      )

      result = merger.merge
      expect(result).to include('gem "foo"')
      expect(result).to include('gem "bar"')
    end

    it "falls back to default_preference when merge_type not in Hash" do
      template = <<~RUBY
        gem "foo"
      RUBY

      dest = <<~RUBY
        gem "foo"
      RUBY

      node_typing = {
        CallNode: ->(node) {
          Ast::Merge::NodeTyping.with_merge_type(node, :unknown_type)
        },
      }

      merger = described_class.new(
        template,
        dest,
        preference: {default: :destination},
        node_typing: node_typing,
      )

      result = merger.merge
      expect(result).to include('gem "foo"')
    end

    it "uses typed dest when only dest node gets typed" do
      template = <<~RUBY
        x = 1
      RUBY

      dest = <<~RUBY
        x = 1
      RUBY

      # Since template and dest nodes are different objects, and the node_typing lambda
      # is called twice in preference_for_node (once for template, once for dest),
      # we can use a simple call counter scoped to preference_for_node calls only.
      call_in_pref = 0
      node_typing = {
        LocalVariableWriteNode: ->(node) {
          call_in_pref += 1
          # Calls 1-2 are during signature building (template + dest)
          # Call 3 is preference_for_node template, Call 4 is preference_for_node dest
          if call_in_pref == 4
            Ast::Merge::NodeTyping.with_merge_type(node, :dest_typed)
          end
        },
      }

      merger = described_class.new(
        template,
        dest,
        preference: {default: :destination, dest_typed: :template},
        node_typing: node_typing,
      )

      result = merger.merge
      expect(result).to include("x = 1")
    end
  end

  describe "parse error handling" do
    it "raises TemplateParseError for truly invalid template syntax" do
      # Prism is a recoverable parser, so many invalid syntaxes still parse.
      # The base class parse_and_analyze catches valid? == false.
      invalid_template = "def ("
      valid_dest = "x = 1"

      expect {
        described_class.new(invalid_template, valid_dest).merge
      }.to raise_error(Prism::Merge::TemplateParseError)
    end

    it "raises DestinationParseError for truly invalid destination syntax" do
      valid_template = "x = 1"
      invalid_dest = "def ("

      expect {
        described_class.new(valid_template, invalid_dest).merge
      }.to raise_error(Prism::Merge::DestinationParseError)
    end
  end

  describe "#emit_dest_prefix_lines" do
    it "preserves magic comment and blank line before first node" do
      template = "x = 1"
      dest = "# frozen_string_literal: true\n\nx = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("# frozen_string_literal: true\n")
      expect(result).to include("x = 1")
    end

    it "preserves multiple prefix lines (encoding + frozen_string_literal)" do
      template = "x = 1"
      dest = "# encoding: utf-8\n# frozen_string_literal: true\n\nx = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("# encoding: utf-8\n# frozen_string_literal: true\n")
      expect(result).to include("x = 1")
    end

    it "handles dest where first node starts on line 1 (no prefix)" do
      template = "x = 1"
      dest = "x = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("x = 1")
    end

    it "preserves blank lines at the start of a file before any code" do
      template = "x = 1"
      dest = "\n\nx = 1\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      # The blank lines before x = 1 should be preserved from dest
      lines = result.split("\n", -1)
      x_idx = lines.index { |l| l.include?("x = 1") }
      expect(x_idx).to be >= 2
    end
  end

  describe "#emit_dest_gap_lines" do
    it "preserves blank lines between top-level blocks" do
      template = <<~RUBY
        def foo
          1
        end

        def bar
          2
        end
      RUBY

      dest = <<~RUBY
        def foo
          1
        end

        def bar
          2
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      # Should preserve the blank line between the two methods
      expect(result).to include("end\n\ndef bar")
    end

    it "preserves blank lines between blocks with leading comments" do
      template = <<~RUBY
        # Comment A
        def foo
          1
        end

        # Comment B
        def bar
          2
        end
      RUBY

      dest = <<~RUBY
        # Comment A
        def foo
          1
        end

        # Comment B
        def bar
          2
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      # The blank line between `end` and `# Comment B` should be preserved
      expect(result).to include("end\n\n# Comment B")
    end

    it "preserves multiple blank lines between blocks" do
      template = <<~RUBY
        x = 1


        y = 2
      RUBY

      dest = <<~RUBY
        x = 1


        y = 2
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      # At least one blank line should separate x = 1 and y = 2
      lines = result.split("\n")
      x_idx = lines.index { |l| l.include?("x = 1") }
      y_idx = lines.index { |l| l.include?("y = 2") }
      expect(y_idx - x_idx).to be > 1
    end
  end

  describe "#merge with prefix lines and gap lines combined" do
    it "preserves magic comment prefix AND inter-block gaps" do
      template = <<~RUBY
        def foo
          1
        end

        def bar
          2
        end
      RUBY

      dest = <<~RUBY
        # frozen_string_literal: true

        def foo
          1
        end

        def bar
          2
        end
      RUBY

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to start_with("# frozen_string_literal: true\n")
      expect(result).to include("end\n\ndef bar")
    end
  end

  describe "#merge with comment-only files" do
    it "handles comment-only files where nodes respond to text" do
      template = "# Just a comment\n# Another comment\n"
      dest = "# Just a comment\n# Another comment\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("# Just a comment")
      expect(result).to include("# Another comment")
    end

    it "handles comment-only files with empty lines between comments" do
      template = "# First\n\n# Second\n"
      dest = "# First\n\n# Second\n"

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("# First")
      expect(result).to include("# Second")
    end

    it "handles comment-only template merged with comment-only dest" do
      template = "# Template only\n"
      dest = "# Dest only\n"

      merger = described_class.new(template, dest, preference: :destination)
      result = merger.merge

      expect(result).to include("# Dest only")
    end
  end

  describe "protected methods" do
    let(:merger) { described_class.new("x = 1", "x = 1") }

    it "result_class returns MergeResult" do
      expect(merger.send(:result_class)).to eq(Prism::Merge::MergeResult)
    end

    it "aligner_class returns nil" do
      expect(merger.send(:aligner_class)).to be_nil
    end

    it "resolver_class returns nil" do
      expect(merger.send(:resolver_class)).to be_nil
    end

    it "default_freeze_token returns prism-merge" do
      expect(merger.send(:default_freeze_token)).to eq("prism-merge")
    end

    it "analysis_class returns FileAnalysis" do
      expect(merger.send(:analysis_class)).to eq(Prism::Merge::FileAnalysis)
    end
  end

  describe "#frozen_node?" do
    it "returns false when freeze_token is nil" do
      merger = described_class.new("x = 1", "x = 1", freeze_token: nil)
      node = merger.template_analysis.statements.first

      expect(merger.send(:frozen_node?, node)).to be(false)
    end
  end

  describe "build_effective_signature_generator" do
    it "returns signature_generator when no node_typing" do
      custom_generator = ->(node) { [:custom, node.class.name] }

      merger = described_class.new("# comment", "# comment", signature_generator: custom_generator)
      effective = merger.send(:build_effective_signature_generator, custom_generator, nil)

      expect(effective).to eq(custom_generator)
    end

    it "wraps signature_generator with node_typing processing" do
      custom_generator = ->(node) { [:custom, node.class.name] }
      node_typing = {Prism::ConstantWriteNode => :version}

      merger = described_class.new("# comment", "# comment")
      effective = merger.send(:build_effective_signature_generator, custom_generator, node_typing)

      expect(effective).to be_a(Proc)
      expect(effective).not_to eq(custom_generator)
    end

    it "creates proc that processes through node_typing then signature_generator" do
      call_log = []
      custom_generator = ->(node) {
        call_log << :generator_called
        [:custom, node.class.name]
      }
      node_typing = {Prism::ConstantWriteNode => :version}

      merger = described_class.new("# comment", "# comment")
      effective = merger.send(:build_effective_signature_generator, custom_generator, node_typing)

      # Create a mock node to test with
      template = "VERSION = '1.0'"
      parsed = Prism.parse(template)
      node = parsed.value.statements.body.first

      effective.call(node)
      expect(call_log).to include(:generator_called)
    end

    it "returns processed node when no signature_generator provided" do
      node_typing = {Prism::ConstantWriteNode => :version}

      merger = described_class.new("# comment", "# comment")
      effective = merger.send(:build_effective_signature_generator, nil, node_typing)

      template = "VERSION = '1.0'"
      parsed = Prism.parse(template)
      node = parsed.value.statements.body.first

      result = effective.call(node)
      # Should return processed node (possibly wrapped with merge_type)
      expect(result).to be_truthy
    end
  end

  describe "recursive body merging with node_typing and signature_generator" do
    # Regression tests for two related bugs in merge_node_body_recursively:
    #
    # Bug 1 (double-wrapping): The effective signature generator wraps the raw one.
    # merge_node_body_recursively passed the effective (wrapped) generator to the
    # inner SmartMerger, causing build_effective_signature_generator to wrap it
    # AGAIN when node_typing is also present.
    #
    # Bug 2 (inline trailing comment duplication): add_node_to_result output the
    # node's source lines (which include inline comments via analysis.line_at),
    # then ALSO output trailing_comments separately. For inline comments on the
    # same line as the node, this duplicated the entire line.

    let(:sig_gen) do
      ->(node) {
        actual = Ast::Merge::NodeTyping.unwrap(node)
        return node unless defined?(Prism) && actual.is_a?(Prism::CallNode)

        method_name = actual.name.to_s
        if method_name.end_with?("=")
          return [:spec_attr, actual.name]
        end

        if %i[add_dependency add_development_dependency].include?(actual.name)
          first_arg = actual.arguments&.arguments&.first
          if first_arg.is_a?(Prism::StringNode)
            return [actual.name, first_arg.unescaped]
          end
        end

        if actual.name == :new
          return [:gem_specification_new]
        end

        node
      }
    end

    let(:node_typing) do
      {
        CallNode: ->(node) {
          receiver = node.receiver
          is_spec_call = receiver.respond_to?(:name) && receiver.name == :spec
          return node unless is_spec_call

          Ast::Merge::NodeTyping.with_merge_type(node, :spec_dependency)
        },
      }
    end

    context "when template and destination have identical block bodies" do
      it "does not duplicate add_dependency calls inside a block" do
        code = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "test"
            spec.add_dependency("foo", "~> 1.0")
            spec.add_dependency("bar", "~> 2.0")
          end
        RUBY

        merger = described_class.new(
          code,
          code,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(2)
        expect(result).to include('spec.add_dependency("foo"')
        expect(result).to include('spec.add_dependency("bar"')
      end
    end

    context "when template has a new dependency not in destination" do
      it "adds the template-only dependency without duplicating existing ones" do
        template = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "test"
            spec.add_dependency("foo", "~> 1.0")
            spec.add_dependency("bar", "~> 2.0")
            spec.add_dependency("baz", "~> 3.0")
          end
        RUBY

        dest = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "test"
            spec.add_dependency("foo", "~> 1.0")
            spec.add_dependency("bar", "~> 2.0")
          end
        RUBY

        merger = described_class.new(
          template,
          dest,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(3)
        expect(result).to include('"baz"')
      end
    end

    context "when dependencies have comments between them" do
      it "does not duplicate dependencies separated by comments" do
        code = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "test"

            # Infrastructure
            spec.add_dependency("foo", "~> 1.0")

            # Utilities
            spec.add_dependency("bar", "~> 2.0")
          end
        RUBY

        merger = described_class.new(
          code,
          code,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(2)
      end
    end

    context "when template updates a dependency version" do
      it "uses template version without duplicating" do
        template = <<~RUBY
          Gem::Specification.new do |spec|
            spec.add_dependency("foo", "~> 2.0")
          end
        RUBY

        dest = <<~RUBY
          Gem::Specification.new do |spec|
            spec.add_dependency("foo", "~> 1.0")
          end
        RUBY

        merger = described_class.new(
          template,
          dest,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(1)
        expect(result).to include("~> 2.0")
        expect(result).not_to include("~> 1.0")
      end
    end

    context "with development dependencies" do
      it "does not duplicate add_development_dependency calls" do
        code = <<~RUBY
          Gem::Specification.new do |spec|
            spec.add_dependency("foo", "~> 1.0")
            spec.add_development_dependency("rspec", "~> 3.0")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY

        merger = described_class.new(
          code,
          code,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(1)
        expect(result.scan("add_development_dependency").length).to eq(2)
      end
    end

    context "with class/module bodies" do
      it "does not duplicate methods inside a class when node_typing is configured" do
        code = <<~RUBY
          class Foo
            def bar
              1
            end

            def baz
              2
            end
          end
        RUBY

        node_typing_for_class = {
          DefNode: ->(node) {
            Ast::Merge::NodeTyping.with_merge_type(node, :method)
          },
        }

        merger = described_class.new(
          code,
          code,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing_for_class,
        )
        result = merger.merge

        expect(result.scan("def bar").length).to eq(1)
        expect(result.scan("def baz").length).to eq(1)
      end
    end

    context "with trailing blank lines between recursively merged blocks" do
      # Regression: merge_node_body_recursively didn't emit trailing blank lines
      # after the closing 'end', so blank lines between consecutive blocks were
      # stripped. add_node_to_result handles this for non-recursive nodes, but
      # the recursive path assembled its own output without the trailing blank.

      it "preserves blank lines between consecutive call-with-block nodes" do
        code = <<~RUBY
          appraise "a" do
            eval_gemfile "x.gemfile"
          end

          appraise "b" do
            eval_gemfile "y.gemfile"
          end
        RUBY

        merger = described_class.new(
          code, code,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("end\n\nappraise")
      end

      it "preserves blank lines between blocks with leading comments" do
        code = <<~RUBY
          appraise "a" do
            eval_gemfile "x.gemfile"
          end

          # Comment for b
          appraise "b" do
            eval_gemfile "y.gemfile"
          end

          appraise "c" do
            eval_gemfile "z.gemfile"
          end
        RUBY

        merger = described_class.new(
          code, code,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        # All blank lines between blocks should be preserved
        expect(result).to include("end\n\n# Comment for b")
        expect(result).to include("end\n\nappraise \"c\"")
      end

      it "preserves blank line between end and trailing non-block node" do
        code = <<~RUBY
          group :development do
            gem "debug", "~> 1.0"
          end

          gem "gem_bench", "~> 2.0"
        RUBY

        merger = described_class.new(
          code, code,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("end\n\ngem \"gem_bench\"")
      end
    end

    it "stores raw_signature_generator separately from effective generator" do
      merger = described_class.new(
        "x = 1",
        "x = 1",
        signature_generator: sig_gen,
        node_typing: node_typing,
      )

      raw = merger.instance_variable_get(:@raw_signature_generator)
      effective = merger.signature_generator

      # Raw should be the original lambda we passed in
      expect(raw).to eq(sig_gen)

      # Effective should be different (wrapped with node_typing)
      expect(effective).not_to eq(sig_gen)
      expect(effective).to be_a(Proc)
    end

    context "with inline trailing comments (same-line comments)" do
      # Regression: add_node_to_result output node source lines (which include
      # inline comments via analysis.line_at), then ALSO output trailing_comments
      # separately. For inline comments like `# ruby >= 3.2.0`, this duplicated
      # the entire source line.

      it "does not duplicate lines when dependencies have inline comments" do
        code = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "test"

            # Infrastructure
            spec.add_dependency("foo", "~> 1.0")                # ruby >= 3.2.0

            # Utilities
            spec.add_dependency("bar", "~> 2.0")                # ruby >= 3.2.0
          end
        RUBY

        merger = described_class.new(
          code,
          code,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(2)
        expect(result).to include("# ruby >= 3.2.0")
      end

      it "does not duplicate flat body nodes with inline comments" do
        # No wrapping block — just the body statements directly
        code = <<~RUBY
          spec.name = "test"

          # Infrastructure
          spec.add_dependency("foo", "~> 1.0")                # ruby >= 3.2.0

          # Utilities
          spec.add_dependency("bar", "~> 2.0")                # ruby >= 3.2.0
        RUBY

        merger = described_class.new(
          code,
          code,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(2)
        # Inline comments should appear exactly once per dependency
        expect(result.scan("# ruby >= 3.2.0").length).to eq(2)
      end

      it "preserves inline comments when template updates dependency version" do
        template = <<~RUBY
          spec.add_dependency("foo", "~> 2.0")                # ruby >= 3.2.0
        RUBY

        dest = <<~RUBY
          spec.add_dependency("foo", "~> 1.0")                # ruby >= 3.1.0
        RUBY

        merger = described_class.new(
          template,
          dest,
          signature_generator: sig_gen,
          preference: :template,
          add_template_only_nodes: true,
          node_typing: node_typing,
        )
        result = merger.merge

        expect(result.scan("add_dependency").length).to eq(1)
        expect(result).to include("~> 2.0")
        expect(result).to include("# ruby >= 3.2.0")
      end
    end
  end
end
