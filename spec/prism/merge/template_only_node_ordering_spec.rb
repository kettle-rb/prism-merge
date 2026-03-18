# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "template-only node position-aware ordering" do
    context "when template-only node is at the end of the template (trailing)" do
      let(:template) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-jem:freeze
          # Frozen content preserved across merges
          # kettle-jem:unfreeze

          appraise "unlocked_deps" do
            eval_gemfile "modular/coverage.gemfile"
          end

          appraise "style" do
            eval_gemfile "modular/style.gemfile"
          end

          appraise "templating" do
            eval_gemfile "modular/templating.gemfile"
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-jem:freeze
          # Frozen content preserved across merges
          # kettle-jem:unfreeze

          appraise "unlocked_deps" do
            eval_gemfile "modular/coverage.gemfile"
          end

          appraise "style" do
            eval_gemfile "modular/style.gemfile"
          end
        RUBY
      end

      it "places template-only node after its preceding matched node (style), not at the beginning" do
        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "kettle-jem",
        )
        result = merger.merge

        # The template-only "templating" block should be present
        expect(result).to include('appraise "templating"')

        # The "templating" block must come AFTER the "style" block (its predecessor in template)
        style_pos = result.index('appraise "style"')
        templating_pos = result.index('appraise "templating"')
        expect(templating_pos).to be > style_pos,
          "Expected 'templating' appraisal to appear after 'style' appraisal, " \
          "but 'templating' was at position #{templating_pos} and 'style' was at #{style_pos}.\n\n" \
          "Result:\n#{result}"

        # The "templating" block must NOT be between the magic comment and the freeze block
        freeze_pos = result.index("kettle-jem:freeze")
        expect(templating_pos).to be > freeze_pos,
          "Expected 'templating' appraisal to appear after freeze block, " \
          "but it was inserted before. Result:\n#{result}"
      end
    end

    context "when template-only node is between two matched nodes (interleaved)" do
      let(:template) do
        <<~RUBY
          # frozen_string_literal: true

          def shared_a
            :a
          end

          def template_only_between
            :new
          end

          def shared_b
            :b
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # frozen_string_literal: true

          def shared_a
            :a_dest
          end

          def shared_b
            :b_dest
          end
        RUBY
      end

      it "places template-only node between its matched neighbors, not at beginning or end" do
        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("def template_only_between")

        # template_only_between must come AFTER shared_a (its predecessor in template)
        shared_a_pos = result.index("def shared_a")
        template_only_pos = result.index("def template_only_between")
        shared_b_pos = result.index("def shared_b")

        expect(template_only_pos).to be > shared_a_pos,
          "Expected template-only node to appear after shared_a.\n\nResult:\n#{result}"

        # template_only_between must come BEFORE shared_b (its successor in template)
        expect(template_only_pos).to be < shared_b_pos,
          "Expected template-only node to appear before shared_b, " \
          "but it was at position #{template_only_pos} and shared_b was at #{shared_b_pos}.\n\n" \
          "Result:\n#{result}"
      end
    end

    context "when template-only node is before the first matched node (prefix)" do
      let(:template) do
        <<~RUBY
          # frozen_string_literal: true

          TEMPLATE_ONLY_PREFIX = true

          def shared_method
            :template
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # frozen_string_literal: true

          def shared_method
            :dest
          end
        RUBY
      end

      it "places template-only node before the first matched node" do
        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("TEMPLATE_ONLY_PREFIX = true")

        # prefix template-only should come BEFORE shared_method
        prefix_pos = result.index("TEMPLATE_ONLY_PREFIX")
        shared_pos = result.index("def shared_method")
        expect(prefix_pos).to be < shared_pos,
          "Expected prefix template-only node before shared_method.\n\nResult:\n#{result}"
      end
    end

    context "when multiple template-only nodes are in different positions" do
      let(:template) do
        <<~RUBY
          # frozen_string_literal: true

          PREFIX_ONLY = true

          def shared_a
            :a
          end

          BETWEEN_ONLY = true

          def shared_b
            :b
          end

          TRAILING_ONLY = true
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # frozen_string_literal: true

          def shared_a
            :a_dest
          end

          def shared_b
            :b_dest
          end
        RUBY
      end

      it "preserves each template-only node's relative position among matched nodes" do
        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("PREFIX_ONLY")
        expect(result).to include("BETWEEN_ONLY")
        expect(result).to include("TRAILING_ONLY")

        prefix_pos = result.index("PREFIX_ONLY")
        shared_a_pos = result.index("def shared_a")
        between_pos = result.index("BETWEEN_ONLY")
        shared_b_pos = result.index("def shared_b")
        trailing_pos = result.index("TRAILING_ONLY")

        # PREFIX_ONLY before shared_a
        expect(prefix_pos).to be < shared_a_pos,
          "Expected PREFIX_ONLY before shared_a.\n\nResult:\n#{result}"

        # BETWEEN_ONLY after shared_a and before shared_b
        expect(between_pos).to be > shared_a_pos,
          "Expected BETWEEN_ONLY after shared_a.\n\nResult:\n#{result}"
        expect(between_pos).to be < shared_b_pos,
          "Expected BETWEEN_ONLY before shared_b.\n\nResult:\n#{result}"

        # TRAILING_ONLY after shared_b
        expect(trailing_pos).to be > shared_b_pos,
          "Expected TRAILING_ONLY after shared_b.\n\nResult:\n#{result}"
      end
    end

    context "with destination-only nodes interspersed" do
      let(:template) do
        <<~RUBY
          # frozen_string_literal: true

          def shared
            :template
          end

          def template_only
            :new
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # frozen_string_literal: true

          DEST_ONLY = true

          def shared
            :dest
          end
        RUBY
      end

      it "preserves dest-only nodes and inserts template-only nodes at their template position" do
        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("DEST_ONLY")
        expect(result).to include("def template_only")

        dest_only_pos = result.index("DEST_ONLY")
        shared_pos = result.index("def shared")
        template_only_pos = result.index("def template_only")

        # DEST_ONLY stays before shared (preserving dest order)
        expect(dest_only_pos).to be < shared_pos,
          "Expected DEST_ONLY before shared.\n\nResult:\n#{result}"

        # template_only comes after shared (its anchor in template)
        expect(template_only_pos).to be > shared_pos,
          "Expected template_only after shared.\n\nResult:\n#{result}"
      end
    end

    context "with prefix lines (shebang + magic comment)" do
      it "keeps destination prefix lines ahead of prefix template-only nodes" do
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

        result = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        ).merge

        # Dest prefix lines always come first
        expect(result).to start_with("#!/usr/bin/env ruby\n# frozen_string_literal: false\n")
        expect(result).to include("class Example")
        expect(result).to include("TEMPLATE_ONLY = true")

        # TEMPLATE_ONLY is a prefix node (before class Example in template)
        # so it should appear before class Example
        template_only_pos = result.index("TEMPLATE_ONLY")
        class_pos = result.index("class Example")
        expect(template_only_pos).to be < class_pos,
          "Expected prefix template-only node before matched class Example.\n\nResult:\n#{result}"
      end
    end
  end
end
