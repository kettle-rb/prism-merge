# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "positional comment block deduplication" do
    # Comment blocks surrounded by gaps (blank lines) in structured code are
    # often positional — they belong to a place in the file rather than to the
    # specific AST node that follows them. When nodes move, get removed, or get
    # added during a merge, greedy leading-comment attachment by the parser can
    # attach the same positional comment block to different nodes in template
    # vs destination, causing the merged output to contain duplicate copies.
    #
    # These specs verify that the merger produces exactly one copy of such a
    # positional comment block regardless of which node it's attached to in
    # each side, and regardless of merge options (signature_generator,
    # preference, add_missing).

    let(:note_block) do
      <<~COMMENT.chomp
        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.
        #       However, development dependencies in gemspec will install on
        #       all versions of Ruby that will run in CI.
      COMMENT
    end

    context "when a gap-separated comment block precedes different nodes in template vs dest" do
      # Template: NOTE block → node_a (the first dev dep after the comment)
      # Dest:     NOTE block → node_b (a different dep, because node_a was removed)
      # The parser attaches NOTE as leading comments of node_a in template
      # and as leading comments of node_b in dest. A naive merge emits both.

      let(:template) do
        <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"

            spec.add_dependency("utils", "~> 1.0")

            #{note_block}

            # Dev tools
            spec.add_development_dependency("dev-tool", "~> 2.0")

            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"

            spec.add_dependency("utils", "~> 1.0")

            ### Testing is runtime for this gem!
            spec.add_dependency("rspec", "~> 3.0")

            #{note_block}

            spec.add_development_dependency("my-test-helper", "~> 1.0")
            # Dev tools
            spec.add_development_dependency("dev-tool", "~> 2.0")

            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      end

      it "emits exactly one copy of the NOTE block without options" do
        merged = described_class.new(template, dest).merge
        expect(merged.scan("NOTE: It is preferable").count).to eq(1),
          "Expected exactly 1 NOTE block, got #{merged.scan("NOTE: It is preferable").count}.\n\nMerged output:\n#{merged}"
      end

      it "emits exactly one copy of the NOTE block with preference: :template and signature_generator" do
        sig_gen = ->(node) do
          actual = node.respond_to?(:__getobj__) ? node.__getobj__ : node
          next node unless actual.is_a?(Prism::CallNode)

          if %i[add_dependency add_development_dependency].include?(actual.name)
            first_arg = actual.arguments&.arguments&.first
            next [actual.name, first_arg.unescaped] if first_arg.is_a?(Prism::StringNode)
          end
          if actual.name == :new && actual.receiver&.slice&.include?("Gem::Specification")
            next [:gem_specification_new]
          end
          if actual.name.to_s.end_with?("=") && actual.receiver&.slice&.strip == "spec"
            next [:spec_attr, actual.name]
          end
          node
        end

        merged = described_class.new(
          template, dest,
          preference: :template,
          add_missing: true,
          signature_generator: sig_gen,
        ).merge

        expect(merged.scan("NOTE: It is preferable").count).to eq(1),
          "Expected exactly 1 NOTE block, got #{merged.scan("NOTE: It is preferable").count}.\n\nMerged output:\n#{merged}"
      end
    end

    context "when a node is removed from template but its leading comment block remains in dest" do
      # Template has: comment_block → node_a → node_b
      # Dest has:     comment_block → node_b  (node_a removed by user)
      # Parser attaches comment_block to node_a in template, node_b in dest.
      # If add_missing: true, template's node_a is added, bringing the comment
      # block again, duplicating the dest's copy.

      let(:template) do
        <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"

            #{note_block}

            # Section A
            spec.add_development_dependency("gem-a", "~> 1.0")

            # Section B
            spec.add_development_dependency("gem-b", "~> 2.0")
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"

            #{note_block}

            # Section B
            spec.add_development_dependency("gem-b", "~> 2.0")
          end
        RUBY
      end

      let(:sig_gen) do
        ->(node) do
          actual = node.respond_to?(:__getobj__) ? node.__getobj__ : node
          next node unless actual.is_a?(Prism::CallNode)

          if %i[add_dependency add_development_dependency].include?(actual.name)
            first_arg = actual.arguments&.arguments&.first
            next [actual.name, first_arg.unescaped] if first_arg.is_a?(Prism::StringNode)
          end
          if actual.name == :new && actual.receiver&.slice&.include?("Gem::Specification")
            next [:gem_specification_new]
          end
          if actual.name.to_s.end_with?("=") && actual.receiver&.slice&.strip == "spec"
            next [:spec_attr, actual.name]
          end
          node
        end
      end

      it "emits exactly one copy of the NOTE block" do
        merged = described_class.new(
          template, dest,
          preference: :template,
          add_missing: true,
          signature_generator: sig_gen,
        ).merge

        expect(merged.scan("NOTE: It is preferable").count).to eq(1),
          "Expected exactly 1 NOTE block, got #{merged.scan("NOTE: It is preferable").count}.\n\nMerged output:\n#{merged}"
      end
    end

    context "when identical comment blocks are leading on matched nodes from different sources" do
      # Both template and dest have the same gap-separated comment block,
      # but preference: :template means the template node is emitted.
      # The dest node was also going to emit its copy — should be deduplicated.

      let(:template) do
        <<~RUBY
          def setup
            # Important configuration note:
            # This block documents the setup contract.
            # All callers must respect the return value.

            configure_defaults
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          def setup
            # Important configuration note:
            # This block documents the setup contract.
            # All callers must respect the return value.

            configure_defaults
            configure_extras
          end
        RUBY
      end

      it "emits exactly one copy of the comment block" do
        merged = described_class.new(template, dest, preference: :template).merge
        expect(merged.scan("Important configuration note").count).to eq(1),
          "Expected exactly 1 comment block, got #{merged.scan("Important configuration note").count}.\n\nMerged output:\n#{merged}"
      end
    end
  end
end
