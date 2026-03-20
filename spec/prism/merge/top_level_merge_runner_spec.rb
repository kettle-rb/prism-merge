# frozen_string_literal: true

RSpec.describe Prism::Merge::TopLevelMergeRunner do
  def build_merger(template, dest, preference: :template, add_template_only_nodes: false, signature_generator: nil, **options)
    Prism::Merge::SmartMerger.new(
      template,
      dest,
      preference: preference,
      add_template_only_nodes: add_template_only_nodes,
      signature_generator: signature_generator,
      **options,
    )
  end

  def merge_with_runner(template:, dest:, **options)
    merger = build_merger(template, dest, **options)
    described_class.new(merger: merger).merge.to_s
  end

  describe "#merge" do
    it "routes comment-only files through the extracted comment-only merger path" do
      template = <<~RUBY
        # frozen_string_literal: true

        # Template note
      RUBY

      dest = <<~RUBY
        # Destination note
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq("# frozen_string_literal: true\n")
    end

    it "inserts prefix template-only nodes before the first matched dest node" do
      template = <<~RUBY
        # frozen_string_literal: true

        TEMPLATE_ONLY = true

        class Example
        end
      RUBY

      dest = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: false

        class Example
        end
      RUBY

      result = merge_with_runner(
        template: template,
        dest: dest,
        preference: :template,
        add_template_only_nodes: true,
      )

      # Destination prefix lines (shebang + magic comment) come first
      expect(result).to start_with("#!/usr/bin/env ruby\n# frozen_string_literal: false\n")
      expect(result).to include("class Example")
      expect(result).to include("TEMPLATE_ONLY = true")
      # TEMPLATE_ONLY precedes class Example in the template, so it's a prefix node
      template_only_pos = result.index("TEMPLATE_ONLY = true")
      class_pos = result.index("class Example")
      expect(template_only_pos).to be < class_pos,
        "Expected prefix template-only node before matched class Example.\nResult:\n#{result}"
    end

    it "does not double-emit the interstitial blank line after a template-only prefix node" do
      template = <<~RUBY
        # frozen_string_literal: true

        TEMPLATE_ONLY = true

        class Example
        end
      RUBY

      dest = <<~RUBY
        # frozen_string_literal: true

        class Example
        end
      RUBY

      result = merge_with_runner(
        template: template,
        dest: dest,
        preference: :template,
        add_template_only_nodes: true,
      )

      expect(result).to eq(<<~RUBY)
        # frozen_string_literal: true

        TEMPLATE_ONLY = true

        class Example
        end
      RUBY
    end

    it "preserves destination duplicate matches once template copies are exhausted" do
      signature_generator = lambda do |node|
        if node.is_a?(Prism::CallNode) && node.name == :puts
          [:puts_call]
        else
          node
        end
      end

      template = <<~RUBY
        puts "template"
      RUBY

      dest = <<~RUBY
        puts "destination one"
        puts "destination two"
      RUBY

      result = merge_with_runner(
        template: template,
        dest: dest,
        preference: :destination,
        signature_generator: signature_generator,
      )

      expect(result).to eq(<<~RUBY)
        puts "destination one"
        puts "destination two"
      RUBY
    end

    it "does not re-emit blank gap lines after external trailing comments were already emitted" do
      template = <<~RUBY
        def example
          :template
        end

        AFTER = true
      RUBY

      dest = <<~RUBY
        # User docs
        def example
          :destination
        end # keep end note

        # trailing note

        AFTER = true
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq(<<~RUBY)
        # User docs
        def example
          :template
        end # keep end note

        # trailing note

        AFTER = true
      RUBY
    end

    it "does not re-emit a matched template node's interstitial blank line at EOF when trailing comments follow it" do
      source = <<~RUBY
        # Debugging - Ensure ENV["DEBUG"] == "true" to use debuggers within spec suite
        # Use binding.break, binding.b, or debugger in code
        gem "debug", ">= 1.1"                     # ruby >= 2.7

        # Dev Console - Binding.pry - Irb replacement
        # gem "pry", "~> 0.14"                     # ruby >= 2.0
      RUBY

      result = merge_with_runner(template: source, dest: source, preference: :template)

      expect(result).to eq(source)
    end

    it "skips destination nodes whose line range was already emitted" do
      source = <<~RUBY
        class Example
        end
      RUBY

      merger = build_merger(source, source)
      runner = described_class.new(merger: merger)
      dest_node = merger.dest_analysis.statements.first

      returned_last_output = runner.send(
        :process_dest_node,
        dest_node: dest_node,
        template_by_signature: merger.send(:build_signature_map, merger.template_analysis),
        consumed_template_indices: Set.new,
        sig_cursor: Hash.new(0),
        output_dest_line_ranges: [{start_offset: dest_node.location.start_offset, end_offset: dest_node.location.end_offset}],
        last_output_dest_line: 11,
      )

      expect(returned_last_output).to eq(11)
      expect(merger.result.line_metadata).to eq([])
    end

    it "preserves distinct same-line destination statements instead of collapsing them by line number" do
      template = <<~RUBY
        shared_call
      RUBY

      dest = <<~RUBY
        shared_call; dest_only_call
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq(<<~RUBY)
        shared_call
        dest_only_call
      RUBY
    end

    it "preserves inline comments on destination-only same-line sibling statements" do
      template = <<~RUBY
        shared_call
      RUBY

      dest = <<~RUBY
        shared_call; dest_only_call # keep this
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq(<<~RUBY)
        shared_call
        dest_only_call # keep this
      RUBY
    end

    it "preserves destination EOF blank lines after the last matched node" do
      template = <<~RUBY
        def example
          :template
        end
      RUBY

      dest = "def example\n  :dest\nend\n\n\n\n"

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq("def example\n  :template\nend\n\n\n\n")
    end

    it "does not duplicate interstitial blank lines after a recursively merged wrapper node" do
      template = <<~RUBY
        class Example
          def shared
            :template
          end
        end

        AFTER = true
      RUBY

      dest = <<~RUBY
        class Example
          def shared
            :destination
          end
        end

        AFTER = true
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq(<<~RUBY)
        class Example
          def shared
            :template
          end
        end

        AFTER = true
      RUBY
    end

    it "preserves an interstitial blank line before a later matched node when template preference is used" do
      template = <<~RUBY
        require "a"

        VALUE = [
          1,
          2,
        ]
      RUBY

      dest = <<~RUBY
        require "a"

        VALUE = [
          1,
          3,
        ]
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq(template)
    end

    it "preserves repeated blank lines between leading comments and a recursively merged wrapper" do
      template = <<~RUBY
        # docs


        class Example
          def shared
            :template
          end
        end
      RUBY

      dest = <<~RUBY
        # docs


        class Example
          def shared
            :destination
          end
        end
      RUBY

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq(template)
    end

    it "preserves destination EOF blank lines after destination trailing comments" do
      template = <<~RUBY
        def example
          :template
        end
      RUBY

      dest = "def example\n  :dest\nend\n# tail\n\n\n"

      result = merge_with_runner(template: template, dest: dest, preference: :template)

      expect(result).to eq("def example\n  :template\nend\n# tail\n\n\n")
    end

    it "removes a destination-only top-level node while promoting its preserved comments" do
      template = <<~RUBY
        KEEP = true
      RUBY

      dest = <<~RUBY
        # docs for old setting
        OLD = true # keep inline

        # trailing note

        KEEP = true
      RUBY

      result = merge_with_runner(
        template: template,
        dest: dest,
        preference: :template,
        remove_template_missing_nodes: true,
      )

      expect(result).to eq(<<~RUBY)
        # docs for old setting
        # keep inline

        # trailing note

        KEEP = true
      RUBY
    end

    it "removes destination-only nested nodes inside recursive merges while preserving their leading comments" do
      template = <<~RUBY
        class Example
          def shared
            :template
          end
        end
      RUBY

      dest = <<~RUBY
        class Example
          # helper docs
          def helper
            :dest_only
          end

          def shared
            :destination
          end
        end
      RUBY

      result = merge_with_runner(
        template: template,
        dest: dest,
        preference: :template,
        remove_template_missing_nodes: true,
      )

      expect(result).to eq(<<~RUBY)
        class Example
          # helper docs

          def shared
            :template
          end
        end
      RUBY
    end
  end
end
