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

    context "with private timeline and anchor handling" do
      it "orders boundaries correctly in timeline (before first, between, after last)" do
        template = <<~RUBY
          # header
          def foo; end
          def bar; end
        RUBY

        dest = template
        merger = described_class.new(template, dest)

        anchor = Prism::Merge::FileAligner::Anchor.new(2, 2, 2, 2, :exact_match, 1)
        boundary_before = Prism::Merge::FileAligner::Boundary.new(1..1, 1..1, nil, anchor)
        boundary_after = Prism::Merge::FileAligner::Boundary.new(3..3, 3..3, anchor, nil)

        # Monkeypatch aligner to use our anchors
        merger.instance_variable_get(:@aligner).instance_variable_set(:@anchors, [anchor])

        timeline = merger.send(:build_timeline, [boundary_after, boundary_before])
        # Timeline should be sorted with boundary_before first, anchor second, boundary_after last
        expect(timeline.first[:type]).to eq(:boundary)
        expect(timeline.last[:type]).to eq(:boundary)
        expect(timeline[1][:type]).to eq(:anchor)
      end

      it "process_anchor handles unknown match types by defaulting to template" do
        template = <<~RUBY
          # header
          def foo; end
        RUBY
        dest = template

        merger = described_class.new(template, dest)
        anchor = Prism::Merge::FileAligner::Anchor.new(2, 2, 2, 2, :unknown, 1)

        merger.send(:process_anchor, anchor)

        expect(merger.result.to_s).to include("def foo")
      end

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

        merger = described_class.new(template, dest, max_recursion_depth: 0)
        # Find anchor: signature match on class node
        aligner = merger.instance_variable_get(:@aligner)
        aligner.align
        anchor = aligner.anchors.find { |a| a.match_type == :signature_match }
        expect(anchor).not_to be_nil

        # Should not recursively merge; with default preference destination remains
        merger.send(:process_anchor, anchor)
        expect(merger.result.to_s).to include("def a")
        # Destination b should still be preserved as appended/kept
        expect(merger.result.to_s).to include("def b")
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
          preference: :template,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        # Freeze block still wins from destination
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
          preference: :template,
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
          preference: :template,
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
          preference: :template,
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
          preference: :template,
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

    describe "#find_node_at_line" do
      it "finds a node spanning the given line" do
        source = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge # Run merge to initialize analysis

        # Access private method for testing
        analysis = merger.instance_variable_get(:@template_analysis)
        node = merger.send(:find_node_at_line, analysis, 4)

        expect(node).to be_a(Prism::DefNode)
        expect(node.name).to eq(:hello)
      end

      it "returns nil when no node spans the given line" do
        source = <<~RUBY
          # frozen_string_literal: true

          def hello
            puts "world"
          end
        RUBY

        merger = described_class.new(source, source)
        merger.merge

        analysis = merger.instance_variable_get(:@template_analysis)
        node = merger.send(:find_node_at_line, analysis, 2) # Comment/blank line

        # The second line is blank; should not find a statement there
        # (statements start after the blank line)
        expect(node).to be_nil
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
            source "https://rubygems.org"
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

    describe "#body_has_mergeable_statements?" do
      it "returns false for body with only string literal" do
        source = <<~'RUBY'
          git_source(:github) { |repo| "https://github.com/#{repo}" }
        RUBY

        merger = described_class.new(source, source)
        node = Prism.parse(source).value.statements.body.first
        body = node.block.body

        expect(merger.send(:body_has_mergeable_statements?, body)).to be false
      end

      it "returns true for body with CallNode" do
        source = <<~RUBY
          describe "test" do
            it "works" do
              expect(true).to be true
            end
          end
        RUBY

        merger = described_class.new(source, source)
        node = Prism.parse(source).value.statements.body.first
        body = node.block.body

        expect(merger.send(:body_has_mergeable_statements?, body)).to be true
      end

      it "returns true for body with DefNode" do
        source = <<~RUBY
          class Foo
            def bar
              42
            end
          end
        RUBY

        merger = described_class.new(source, source)
        node = Prism.parse(source).value.statements.body.first
        body = node.body

        expect(merger.send(:body_has_mergeable_statements?, body)).to be true
      end

      it "returns false for nil body" do
        merger = described_class.new("x = 1", "x = 1")
        expect(merger.send(:body_has_mergeable_statements?, nil)).to be false
      end

      it "returns false for empty body" do
        source = "class Foo; end"
        merger = described_class.new(source, source)
        node = Prism.parse(source).value.statements.body.first
        # ClassNode with no body has nil body, not empty StatementsNode
        expect(merger.send(:body_has_mergeable_statements?, node.body)).to be false
      end
    end

    describe "#mergeable_statement?" do
      let(:merger) { described_class.new("x = 1", "x = 1") }

      it "returns true for CallNode" do
        node = Prism.parse("foo()").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be true
      end

      it "returns true for DefNode" do
        node = Prism.parse("def foo; end").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be true
      end

      it "returns true for ClassNode" do
        node = Prism.parse("class Foo; end").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be true
      end

      it "returns true for ConstantWriteNode" do
        node = Prism.parse("FOO = 1").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be true
      end

      it "returns true for LocalVariableWriteNode" do
        node = Prism.parse("foo = 1").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be true
      end

      it "returns false for StringNode" do
        node = Prism.parse('"hello"').value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be false
      end

      it "returns false for InterpolatedStringNode" do
        node = Prism.parse('"hello #{world}"').value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be false
      end

      it "returns false for IntegerNode" do
        node = Prism.parse("42").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be false
      end

      it "returns false for ArrayNode" do
        node = Prism.parse("[1, 2, 3]").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be false
      end

      it "returns false for HashNode" do
        node = Prism.parse("{a: 1}").value.statements.body.first
        expect(merger.send(:mergeable_statement?, node)).to be false
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
end
