# frozen_string_literal: true

require "prism/merge"

RSpec.describe "FrozenWrapper signature matching" do
  let(:fixtures_path) { File.expand_path("../fixtures/reproducible/04_gemspec_duplication", __dir__) }

  describe "when destination node contains freeze markers in its body" do
    let(:template) { File.read(File.join(fixtures_path, "template.rb")) }
    let(:destination) { File.read(File.join(fixtures_path, "destination.rb")) }

    it "does not duplicate nodes - internal freeze markers don't wrap outer block" do
      # With the fix to frozen_node?, nodes with internal freeze markers
      # are NOT wrapped as FrozenWrapper. The freeze marker applies to
      # the nested statement, not the outer block.
      signature_generator = ->(node) do
        return node unless defined?(Prism) && node.is_a?(Prism::CallNode)

        # Match Gem::Specification.new as singleton
        receiver_name = node.receiver&.slice
        if receiver_name&.include?("Gem::Specification") && node.name == :new
          return [:gem_specification_new]
        end

        # Match local variable assignments by name
        node
      end

      merger = Prism::Merge::SmartMerger.new(
        template,
        destination,
        signature_generator: signature_generator,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "kettle-dev",
      )

      result = merger.merge

      # Count occurrences of Gem::Specification.new
      spec_new_count = result.scan("Gem::Specification.new").length

      expect(spec_new_count).to eq(1),
        "Expected exactly 1 Gem::Specification.new block, but found #{spec_new_count}.\n" \
          "Internal freeze markers should not cause outer block to be wrapped.\n" \
          "Result preview (first 500 chars):\n#{result[0, 500]}"
    end

    it "nodes with internal freeze markers are not wrapped as FrozenWrapper" do
      # With frozen_node? fixed, internal freeze markers don't wrap the outer block.
      # Both template and dest nodes should be plain Prism::CallNode instances.
      signature_generator = ->(node) do
        return node unless defined?(Prism) && node.is_a?(Prism::CallNode)

        receiver_name = node.receiver&.slice
        if receiver_name&.include?("Gem::Specification") && node.name == :new
          return [:gem_specification_new]
        end

        node
      end

      template_analysis = Prism::Merge::FileAnalysis.new(
        template,
        freeze_token: "kettle-dev",
        signature_generator: signature_generator,
      )

      dest_analysis = Prism::Merge::FileAnalysis.new(
        destination,
        freeze_token: "kettle-dev",
        signature_generator: signature_generator,
      )

      # Find the Gem::Specification.new nodes
      template_spec_node = template_analysis.statements.find do |node|
        node.is_a?(Prism::CallNode) && node.name == :new &&
          node.receiver&.slice&.include?("Gem::Specification")
      end

      dest_spec_node = dest_analysis.statements.find do |node|
        node.is_a?(Prism::CallNode) && node.name == :new &&
          node.receiver&.slice&.include?("Gem::Specification")
      end

      expect(template_spec_node).not_to be_nil, "Template should have Gem::Specification.new"
      expect(dest_spec_node).not_to be_nil, "Destination should have Gem::Specification.new"

      # Neither node should be wrapped - internal freeze markers don't affect outer block
      expect(template_spec_node).to be_a(Prism::CallNode)
      expect(dest_spec_node).to be_a(Prism::CallNode)
      expect(dest_spec_node).not_to be_a(Ast::Merge::Freezable),
        "Dest node should NOT be wrapped - internal freeze markers apply to nested statements"

      template_sig = template_analysis.generate_signature(template_spec_node)
      dest_sig = dest_analysis.generate_signature(dest_spec_node)

      expect(template_sig).to eq(dest_sig),
        "Signatures should match since neither node is wrapped!\n" \
          "Template signature: #{template_sig.inspect}\n" \
          "Dest signature: #{dest_sig.inspect}"
    end
  end

  describe "minimal reproduction case" do
    # Simpler test case to isolate the issue
    let(:simple_template) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
        end
      RUBY
    end

    let(:simple_destination_with_freeze) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          # prism-merge:freeze
          # Custom frozen content
          # prism-merge:unfreeze
        end
      RUBY
    end

    it "matches nodes when destination contains nested freeze markers" do
      signature_generator = ->(node) do
        return node unless defined?(Prism) && node.is_a?(Prism::CallNode)

        receiver_name = node.receiver&.slice
        if receiver_name&.include?("Gem::Specification") && node.name == :new
          return [:gem_specification_new]
        end

        node
      end

      merger = Prism::Merge::SmartMerger.new(
        simple_template,
        simple_destination_with_freeze,
        signature_generator: signature_generator,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "prism-merge",
      )

      result = merger.merge
      spec_new_count = result.scan("Gem::Specification.new").length

      expect(spec_new_count).to eq(1),
        "Expected 1 Gem::Specification.new, found #{spec_new_count}.\n" \
          "Full result:\n#{result}"
    end

    it "shows that nodes with internal freeze markers are NOT wrapped" do
      dest_analysis = Prism::Merge::FileAnalysis.new(
        simple_destination_with_freeze,
        freeze_token: "prism-merge",
      )

      spec_node = dest_analysis.statements.find do |node|
        node.is_a?(Prism::CallNode) && node.name == :new
      end

      # The node should NOT be wrapped because the freeze markers are INSIDE the body,
      # not in leading comments. In Ruby, freeze markers apply to the specific
      # statement they precede, not to enclosing blocks.
      is_frozen = spec_node.is_a?(Ast::Merge::Freezable)

      # Document the correct behavior
      puts "Node class: #{spec_node.class}"
      puts "Is Freezable: #{is_frozen}"
      puts "Responds to unwrap: #{spec_node.respond_to?(:unwrap)}"

      # This test documents the CORRECT behavior - the node is NOT wrapped
      # because nested freeze markers belong to nested statements, not outer blocks
      expect(is_frozen).to be(false),
        "Node should NOT be wrapped as Freezable - internal freeze markers apply to nested statements"
    end
  end
end
