# frozen_string_literal: true

require "spec_helper"

RSpec.describe Prism::Merge::FileAnalysis do
  describe "#initialize" do
    it "parses valid Ruby code" do
      code = "def example\n  puts 'hello'\nend"
      analysis = described_class.new(code)

      expect(analysis.valid?).to be true
      expect(analysis.statements).not_to be_empty
    end

    it "uses Prism's native comment attachment" do
      code = <<~RUBY
        # Leading comment
        def example
          "hello"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:node]).to be_a(Prism::DefNode)
      expect(node_info[:leading_comments].size).to eq(1)
      expect(node_info[:leading_comments].first.slice).to include("Leading comment")
    end

    it "attaches inline comments via trailing_comments" do
      code = <<~RUBY
        def example
          "hello" # inline comment
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      # The inline comment is attached to the StringNode inside the DefNode
      expect(node_info[:node]).to be_a(Prism::DefNode)

      # Navigate to the StringNode
      statements_node = node_info[:node].body
      string_node = statements_node.body.first

      expect(string_node).to be_a(Prism::StringNode)
      expect(string_node.location.trailing_comments.size).to eq(1)
      expect(string_node.location.trailing_comments.first.slice).to include("inline comment")
    end
  end

  describe "freeze blocks" do
    it "extracts freeze blocks with enclosed statements" do
      code = <<~RUBY
        def method_a
          "a"
        end

        # prism-merge:freeze
        def frozen_method
          "frozen"
        end
        # prism-merge:unfreeze

        def method_b
          "b"
        end
      RUBY

      analysis = described_class.new(code)

      expect(analysis.freeze_blocks.size).to eq(1)
      freeze_node = analysis.freeze_blocks.first

      expect(freeze_node).to be_a(Prism::Merge::FreezeNode)
      expect(freeze_node.start_line).to eq(5)
      expect(freeze_node.end_line).to eq(9)
      expect(freeze_node.nodes.size).to eq(1)
      expect(freeze_node.nodes.first).to be_a(Prism::DefNode)
    end

    it "filters out statements inside freeze blocks from main statements list" do
      code = <<~RUBY
        def method_a
          "a"
        end

        # prism-merge:freeze
        def frozen_method
          "frozen"
        end
        # prism-merge:unfreeze

        def method_b
          "b"
        end
      RUBY

      analysis = described_class.new(code)

      # Should have 3 total nodes: 2 methods + 1 freeze block
      expect(analysis.statements.size).to eq(3)

      # The freeze block contains the frozen method
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.nodes.size).to eq(1)

      # Regular statements should only include method_a and method_b
      regular_methods = analysis.statements.select { |n| n.is_a?(Prism::DefNode) }
      expect(regular_methods.size).to eq(2)
      expect(regular_methods.map { |m| m.name }).to contain_exactly(:method_a, :method_b)
    end

    it "uses custom freeze token when provided" do
      code = <<~RUBY
        # kettle-dev:freeze
        def frozen_method
          "frozen"
        end
        # kettle-dev:unfreeze
      RUBY

      analysis = described_class.new(code, freeze_token: "kettle-dev")

      expect(analysis.freeze_blocks.size).to eq(1)
      expect(analysis.freeze_blocks.first.nodes.size).to eq(1)
    end

    it "raises error for unclosed freeze block inside nested structure" do
      code = <<~RUBY
        class MyClass
          # prism-merge:freeze
          def frozen_method
            "frozen"
          end
        end
      RUBY

      expect {
        described_class.new(code)
      }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError, /Unclosed freeze block.*inside a nested structure/)
    end

    it "allows unclosed freeze block at root level (extends to EOF)" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen_method
          "frozen"
        end
      RUBY

      analysis = described_class.new(code)
      expect(analysis.freeze_blocks.length).to eq(1)
      freeze_block = analysis.freeze_blocks.first
      expect(freeze_block.start_line).to eq(1)
      expect(freeze_block.end_line).to eq(4) # extends to end of file
    end

    it "raises error for unfreeze without freeze" do
      code = <<~RUBY
        def method
          "test"
        end
        # prism-merge:unfreeze
      RUBY

      expect {
        described_class.new(code)
      }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError, /without matching freeze/)
    end

    it "raises error for nested freeze blocks" do
      code = <<~RUBY
        # prism-merge:freeze
        def outer
          "outer"
        end
        # prism-merge:freeze
        def inner
          "inner"
        end
        # prism-merge:unfreeze
      RUBY

      expect {
        described_class.new(code)
      }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError, /Nested freeze block/)
    end
  end

  describe "#nodes_with_comments" do
    it "includes leading comments from Prism's attachment" do
      code = <<~RUBY
        # Comment line 1
        # Comment line 2
        def example
          "hello"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:leading_comments].size).to eq(2)
      expect(node_info[:leading_comments].map(&:slice).map(&:strip)).to eq([
        "# Comment line 1",
        "# Comment line 2",
      ])
    end

    it "includes node signature" do
      code = <<~RUBY
        def example(arg1, arg2)
          "hello"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :example, [:arg1, :arg2]])
    end

    it "includes line range" do
      code = <<~RUBY
        def example
          "hello"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:line_range]).to eq(1..3)
    end
  end

  describe "comment attachment behavior" do
    it "attaches comments between methods as leading comments to next method" do
      code = <<~RUBY
        def method_a
          "a"
        end

        # Documentation for method_b
        # Multiple lines
        def method_b
          "b"
        end
      RUBY

      analysis = described_class.new(code)
      method_b_info = analysis.nodes_with_comments.find { |n| n[:node].name == :method_b }

      expect(method_b_info[:leading_comments].size).to eq(2)
      expect(method_b_info[:leading_comments].map(&:slice).map(&:strip)).to include(
        "# Documentation for method_b",
        "# Multiple lines",
      )
    end

    it "attaches trailing comments to last method" do
      code = <<~RUBY
        def method_a
          "a"
        end

        # Trailing documentation
      RUBY

      analysis = described_class.new(code)
      method_a_info = analysis.nodes_with_comments.first

      expect(method_a_info[:inline_comments].size).to eq(1)
      expect(method_a_info[:inline_comments].first.slice).to include("Trailing documentation")
    end

    it "attaches magic comments as leading comments to first node" do
      code = <<~RUBY
        # frozen_string_literal: true

        def example
          "hello"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      magic_comment = node_info[:leading_comments].find do |c|
        c.slice.include?("frozen_string_literal")
      end

      expect(magic_comment).not_to be_nil
    end
  end

  describe "#signature_at" do
    it "returns signature for valid index" do
      code = <<~RUBY
        def example
          "hello"
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:def, :example, []])
    end

    it "returns nil for invalid index" do
      code = "def example\nend"
      analysis = described_class.new(code)

      expect(analysis.signature_at(-1)).to be_nil
      expect(analysis.signature_at(999)).to be_nil
    end
  end

  describe "custom signature generator" do
    it "uses custom signature generator when provided" do
      code = "def example\nend"
      custom_gen = ->(node) { [:custom, node.class.name] }

      analysis = described_class.new(code, signature_generator: custom_gen)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:custom, "Prism::DefNode"])
    end
  end

  describe "#in_freeze_block?" do
    it "returns true for lines inside freeze block" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen
          "frozen"
        end
        # prism-merge:unfreeze
      RUBY

      analysis = described_class.new(code)

      expect(analysis.in_freeze_block?(2)).to be true  # def line
      expect(analysis.in_freeze_block?(3)).to be true  # method body
    end

    it "returns false for lines outside freeze block" do
      code = <<~RUBY
        def regular
          "regular"
        end

        # prism-merge:freeze
        def frozen
          "frozen"
        end
        # prism-merge:unfreeze
      RUBY

      analysis = described_class.new(code)

      expect(analysis.in_freeze_block?(1)).to be false
      expect(analysis.in_freeze_block?(2)).to be false
    end
  end

  describe "#freeze_block_at" do
    it "returns freeze block containing the line" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen
          "frozen"
        end
        # prism-merge:unfreeze
      RUBY

      analysis = described_class.new(code)
      freeze_node = analysis.freeze_block_at(2)

      expect(freeze_node).to be_a(Prism::Merge::FreezeNode)
      expect(freeze_node.start_line).to eq(1)
    end

    it "returns nil for lines outside freeze blocks" do
      code = <<~RUBY
        def regular
          "regular"
        end
      RUBY

      analysis = described_class.new(code)

      expect(analysis.freeze_block_at(1)).to be_nil
    end
  end
end
