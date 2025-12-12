# frozen_string_literal: true

require "spec_helper"

RSpec.describe Prism::Merge::SmartMerger, ".merge" do
  # Signature generator for gemspec files (same as Kettle::Jem::Signatures.gemspec)
  let(:gemspec_signature_generator) do
    ->(node) do
      return node unless node.is_a?(Prism::CallNode)

      method_name = node.name.to_s
      receiver = node.receiver

      # Extract receiver name
      receiver_name = case receiver
      when Prism::CallNode
        receiver.name.to_s
      when Prism::ConstantReadNode
        receiver.name.to_s
      when Prism::ConstantPathNode
        receiver.slice
      else
        receiver&.slice
      end

      # spec.foo = "value" assignments
      if method_name.end_with?("=") && receiver_name == "spec"
        return [:spec_attr, node.name]
      end

      # spec.add_dependency and spec.add_development_dependency
      if %i[add_dependency add_development_dependency add_runtime_dependency].include?(node.name)
        first_arg = node.arguments&.arguments&.first
        if first_arg.is_a?(Prism::StringNode)
          return [node.name, first_arg.unescaped]
        end
      end

      # Gem::Specification.new block
      if receiver_name&.include?("Gem::Specification") && node.name == :new
        return [:gem_specification_new]
      end

      node
    end
  end

  describe "merging gemspec with Gem::Specification.new blocks" do
    # Simple case: both have same structure
    context "when both template and dest have identical structure" do
      let(:template) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
            spec.summary = "Template summary"
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version = "2.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
            spec.summary = "Dest summary"
          end
        RUBY
      end

      it "does not duplicate Gem::Specification.new blocks" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        spec_new_count = result.scan("Gem::Specification.new").count
        expect(spec_new_count).to eq(1), "Expected 1 Gem::Specification.new block, got #{spec_new_count}\n\nResult:\n#{result}"
      end

      it "starts with magic comments, not Gem::Specification" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        first_line = result.lines.first.chomp
        expect(first_line).to eq("# coding: utf-8"), "Expected first line to be magic comment, got: #{first_line}\n\nFull result:\n#{result}"
      end
    end

    # Edge case: dest has MORE content before Gem::Specification.new than template
    context "when dest has more preceding content than template" do
      let(:template) do
        <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.summary = "Template summary"
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          # Custom comment block
          # that spans multiple lines

          gem_version = "2.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
            spec.summary = "Dest summary"
            spec.authors = ["Author"]
          end
        RUBY
      end

      it "does not duplicate Gem::Specification.new blocks" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        spec_new_count = result.scan("Gem::Specification.new").count
        expect(spec_new_count).to eq(1), "Expected 1 Gem::Specification.new block, got #{spec_new_count}\n\nResult:\n#{result}"
      end

      it "preserves dest-only content (gem_version assignment)" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        expect(result).to include('gem_version = "2.0.0"')
      end
    end

    # Edge case: template has MORE content before Gem::Specification.new than dest
    context "when template has more preceding content than dest" do
      let(:template) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          # Template comment block
          # explaining the gemspec

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
            spec.summary = "Template summary"
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.summary = "Dest summary"
            spec.authors = ["Author"]
          end
        RUBY
      end

      it "does not duplicate Gem::Specification.new blocks" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        spec_new_count = result.scan("Gem::Specification.new").count
        expect(spec_new_count).to eq(1), "Expected 1 Gem::Specification.new block, got #{spec_new_count}\n\nResult:\n#{result}"
      end

      it "adds template-only content (gem_version assignment) since add_template_only_nodes is true" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        expect(result).to include('gem_version = "1.0.0"')
      end

      it "starts with magic comment, not Gem::Specification.new" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "test",
        )
        result = merger.merge

        first_line = result.lines.first.chomp
        expect(first_line).not_to match(/Gem::Specification/),
          "First line should NOT be Gem::Specification.new, got: #{first_line}\n\nFull result:\n#{result}"
      end
    end

    # Real-world scenario: mimics the kettle-dev fixture structure
    context "with real-world kettle-dev gemspec scenario" do
      let(:template) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          # kettle-dev:freeze
          # Frozen content here
          # kettle-dev:unfreeze

          gem_version =
            if RUBY_VERSION >= "3.1"
              "from_load"
            else
              "from_require"
            end

          Gem::Specification.new do |spec|
            spec.name = "kettle-dev"
            spec.version = gem_version
            spec.summary = "Template summary"
            spec.files = Dir["lib/**/*.rb"]
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          # kettle-dev:freeze
          # Custom frozen content
          # kettle-dev:unfreeze

          gem_version =
            if RUBY_VERSION >= "3.1"
              "from_load"
            else
              "from_require"
            end

          Gem::Specification.new do |spec|
            spec.name = "kettle-dev"
            spec.version = gem_version
            spec.summary = "Dest summary"
            spec.authors = ["Peter Boling"]
            spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs"]
            spec.add_development_dependency("rake", "~> 13.0")
            spec.add_development_dependency("rspec", "~> 3.0")
          end
        RUBY
      end

      it "does not duplicate Gem::Specification.new blocks" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        spec_new_count = result.scan("Gem::Specification.new").count
        expect(spec_new_count).to eq(1), "Expected 1 Gem::Specification.new block, got #{spec_new_count}\n\nResult:\n#{result}"
      end

      it "starts with magic comments" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        first_two_lines = result.lines.first(2).map(&:chomp)
        expect(first_two_lines[0]).to eq("# coding: utf-8")
        expect(first_two_lines[1]).to eq("# frozen_string_literal: true")
      end

      it "does not output Gem::Specification.new before magic comments" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        # Find positions of key elements
        first_magic_comment = result.index("# coding: utf-8") || result.index("# frozen_string_literal")
        gem_spec_position = result.index("Gem::Specification.new")

        expect(first_magic_comment).to be < gem_spec_position,
          "Magic comments should appear before Gem::Specification.new\n\nResult:\n#{result}"
      end

      it "has gem_version assignment before Gem::Specification.new" do
        merger = described_class.new(
          template,
          dest,
          signature_generator: gemspec_signature_generator,
          preference: :template,
          add_template_only_nodes: true,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        gem_version_pos = result.index("gem_version =")
        gem_spec_pos = result.index("Gem::Specification.new")

        expect(gem_version_pos).not_to be_nil, "gem_version assignment should be present"
        expect(gem_version_pos).to be < gem_spec_pos,
          "gem_version should appear before Gem::Specification.new\n\nResult:\n#{result}"
      end
    end

    context "when debugging signature generation" do
      let(:template) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
          end
        RUBY
      end

      let(:dest) do
        <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version = "2.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
          end
        RUBY
      end

      it "generates [:gem_specification_new] signature for Gem::Specification.new" do
        template_result = Prism.parse(template)
        template_statements = template_result.value.statements.body

        spec_node = template_statements.find do |node|
          node.is_a?(Prism::CallNode) &&
            node.name == :new &&
            node.receiver&.slice&.include?("Gem::Specification")
        end

        expect(spec_node).not_to be_nil, "Could not find Gem::Specification.new in template"

        signature = gemspec_signature_generator.call(spec_node)
        expect(signature).to eq([:gem_specification_new])
      end

      it "generates same signature for both template and dest Gem::Specification.new" do
        template_result = Prism.parse(template)
        dest_result = Prism.parse(dest)

        template_spec_node = template_result.value.statements.body.find do |node|
          node.is_a?(Prism::CallNode) && node.name == :new
        end

        dest_spec_node = dest_result.value.statements.body.find do |node|
          node.is_a?(Prism::CallNode) && node.name == :new
        end

        template_sig = gemspec_signature_generator.call(template_spec_node)
        dest_sig = gemspec_signature_generator.call(dest_spec_node)

        expect(template_sig).to eq(dest_sig)
        expect(template_sig).to eq([:gem_specification_new])
      end
    end
  end
end
