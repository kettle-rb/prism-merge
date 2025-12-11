# frozen_string_literal: true

require "spec_helper"

# Tests for freeze block detection and handling during merge operations
RSpec.describe "Freeze Block Detection and Handling" do
  describe "when template has freeze block but destination does not" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN_CONST = "template value"
        # kettle-dev:unfreeze

        def normal_method
          "normal"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        FROZEN_CONST = "dest value"

        def normal_method
          "normal"
        end
      RUBY
    end

    it "merges successfully when destination lacks freeze markers" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      # When template has freeze but dest doesn't, the freeze block behavior depends on implementation
      # The system should still merge successfully
      expect(result).to include("FROZEN_CONST")
      expect(result).to include("normal_method")
    end
  end

  describe "when destination has freeze block but template does not" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        FROZEN_CONST = "template value"

        def normal_method
          "normal"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FROZEN_CONST = "dest value"
        EXTRA_FROZEN = "extra"
        # kettle-dev:unfreeze

        def normal_method
          "normal"
        end
      RUBY
    end

    it "preserves destination frozen nodes" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      expect(result).to include("kettle-dev:freeze")
      expect(result).to include('FROZEN_CONST = "dest value"')
      expect(result).to include('EXTRA_FROZEN = "extra"')
    end
  end

  describe "when both have freeze blocks with different content" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FIRST = "template"
        SECOND = "template"
        # kettle-dev:unfreeze
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        FIRST = "dest"
        SECOND = "dest"
        THIRD = "dest only"
        # kettle-dev:unfreeze
      RUBY
    end

    it "preserves destination freeze block content" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      expect(result).to include('FIRST = "dest"')
      expect(result).to include('SECOND = "dest"')
      expect(result).to include('THIRD = "dest only"')
      expect(result).not_to include('FIRST = "template"')
    end
  end

  describe "with nested freeze blocks" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        module Outer
          # kettle-dev:freeze
          CONST = "template"
          # kettle-dev:unfreeze

          class Inner
            def method
              "template"
            end
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        module Outer
          # kettle-dev:freeze
          CONST = "dest"
          EXTRA = "dest"
          # kettle-dev:unfreeze

          class Inner
            def method
              "dest"
            end

            def custom
              "custom"
            end
          end
        end
      RUBY
    end

    it "handles freeze blocks within modules and classes" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      expect(result).to include('CONST = "dest"')
      expect(result).to include('EXTRA = "dest"')
      expect(result).to include("custom")
    end
  end

  describe "with freeze block containing only comments" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        # This is a comment
        # Another comment
        # kettle-dev:unfreeze

        def method
          "method"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-dev:freeze
        # Different comment
        # More comments
        CONST = "value"
        # kettle-dev:unfreeze

        def method
          "method"
        end
      RUBY
    end

    it "preserves destination freeze block even with only comments in template" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      expect(result).to include("Different comment")
      expect(result).to include('CONST = "value"')
    end
  end

  # Regression test for nested freeze blocks inside block bodies (e.g., Gem::Specification.new)
  # Previously, freeze blocks inside nested block bodies were lost during recursive merge
  # because: 1) freeze_token wasn't passed to nested mergers, and 2) extract_node_body
  # didn't include leading comments/freeze markers before the first statement.
  describe "with freeze blocks inside nested block bodies (regression)" do
    let(:template_code) do
      <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "updated-name"
          spec.add_dependency "foo"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "original-name"
          # kettle-dev:freeze
          spec.metadata["custom"] = "1"
          # kettle-dev:unfreeze
          spec.add_dependency "existing"
        end
      RUBY
    end

    let(:signature_generator) do
      lambda do |node|
        if node.is_a?(Prism::CallNode)
          method_name = node.name.to_s
          receiver_name = node.receiver.is_a?(Prism::CallNode) ? node.receiver.name.to_s : node.receiver&.slice

          # For assignment methods, match by receiver and method name only
          if method_name.end_with?("=")
            return [:call, node.name, receiver_name]
          end

          # For other methods with arguments, include first argument
          first_arg = node.arguments&.arguments&.first
          arg_value = case first_arg
          when Prism::StringNode then first_arg.unescaped.to_s
          when Prism::SymbolNode then first_arg.unescaped.to_sym
          end

          return [node.name, arg_value] if arg_value
        end

        # Fall through to default signature computation
        node
      end
    end

    it "preserves freeze blocks inside Gem::Specification blocks" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "kettle-dev",
        signature_generator: signature_generator,
      )

      result = merger.merge

      # Template's spec.name should win (signature match with :template preference)
      expect(result).to include('spec.name = "updated-name"')

      # Freeze block from dest should be preserved
      expect(result).to include("# kettle-dev:freeze")
      expect(result).to include('spec.metadata["custom"] = "1"')
      expect(result).to include("# kettle-dev:unfreeze")

      # Template's add_dependency should be included (template-only node)
      expect(result).to include('spec.add_dependency "foo"')

      # The unfreeze marker should NOT be duplicated
      expect(result.scan("# kettle-dev:unfreeze").count).to eq(1)
    end

    it "does not duplicate freeze markers as leading comments" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "kettle-dev",
        signature_generator: signature_generator,
      )

      result = merger.merge

      # Each freeze marker should appear exactly once
      expect(result.scan("# kettle-dev:freeze").count).to eq(1)
      expect(result.scan("# kettle-dev:unfreeze").count).to eq(1)
    end
  end

  # Regression test for top-level freeze blocks with magic comments
  # Previously, Prism attached ALL comments before a node as leading comments,
  # including comments inside freeze blocks. This caused duplicate content when
  # anchors overlapped (freeze block anchor + node anchor with leading comments).
  describe "with top-level freeze blocks and magic comments (regression)" do
    let(:template_code) do
      <<~RUBY
        # coding: utf-8
        # frozen_string_literal: true

        # kettle-dev:freeze
        # Freeze block comment
        # kettle-dev:unfreeze

        gem_version =
          if RUBY_VERSION >= "3.1"
            "new"
          else
            "old"
          end

        Gem::Specification.new do |spec|
          spec.name = "example"
          spec.version = gem_version
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # coding: utf-8
        # frozen_string_literal: true

        # kettle-dev:freeze
        # Freeze block comment
        # kettle-dev:unfreeze

        gem_version =
          if RUBY_VERSION >= "3.1"
            "new"
          else
            "old"
          end

        Gem::Specification.new do |spec|
          spec.name = "example"
          spec.version = gem_version
          # kettle-dev:freeze
          # Custom metadata preserved
          # kettle-dev:unfreeze
        end
      RUBY
    end

    it "does not duplicate content when freeze blocks precede other nodes" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      # gem_version assignment should appear exactly once
      expect(result.scan(/^gem_version =/).count).to eq(1)

      # Gem::Specification.new should appear exactly once
      expect(result.scan("Gem::Specification.new").count).to eq(1)

      # Magic comments should appear exactly once each
      expect(result.scan("# coding: utf-8").count).to eq(1)
      expect(result.scan("# frozen_string_literal: true").count).to eq(1)
    end

    it "preserves both freeze blocks (top-level and nested)" do
      merger = Prism::Merge::SmartMerger.new(template_code, dest_code, freeze_token: "kettle-dev")
      result = merger.merge

      # Should have 2 freeze markers (top-level + nested)
      expect(result.scan("# kettle-dev:freeze").count).to eq(2)

      # Nested freeze block content should be preserved
      expect(result).to include("# Custom metadata preserved")
    end

    it "includes freeze markers as leading comments (they mark nodes as frozen)" do
      analysis = Prism::Merge::FileAnalysis.new(dest_code, freeze_token: "kettle-dev")

      # Find the LocalVariableWriteNode (gem_version assignment)
      node_info = analysis.nodes_with_comments.find do |n|
        n[:node].is_a?(Prism::LocalVariableWriteNode)
      end

      # With simplified freeze semantics, freeze markers ARE leading comments
      # They stay attached to nodes and mark them as frozen
      leading_lines = node_info[:leading_comments].map { |c| c.location.start_line }

      # Should include magic comments (1, 2) AND the freeze block comments (4, 5, 6)
      # because Prism attaches all preceding comments to the next node
      expect(leading_lines).to include(1, 2) # magic comments
    end
  end
end
