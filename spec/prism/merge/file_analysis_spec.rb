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

  describe "#compute_node_signature" do
    # Test node signature generation for various node types
    # These tests cover lines 461-562 in file_analysis.rb

    it "generates signature for SingletonClassNode" do
      code = <<~RUBY
        class << self
          def foo; end
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:singleton_class, "self"])
    end

    it "generates signature for CaseNode" do
      code = <<~RUBY
        case x
        when 1 then :one
        when 2 then :two
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:case, "x"])
    end

    it "generates signature for CaseMatchNode (pattern matching)" do
      code = <<~RUBY
        case x
        in Integer then :int
        in String then :str
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:case_match, "x"])
    end

    it "generates signature for WhileNode" do
      code = <<~RUBY
        while condition
          do_something
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:while, "condition"])
    end

    it "generates signature for UntilNode" do
      code = <<~RUBY
        until done
          work
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:until, "done"])
    end

    it "generates signature for ForNode" do
      code = <<~RUBY
        for i in collection
          process(i)
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:for, "i", "collection"])
    end

    it "generates signature for BeginNode" do
      code = <<~RUBY
        begin
          risky_operation
        rescue => e
          handle(e)
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig.first).to eq(:begin)
      expect(sig.last).to include("risky_operation")
    end

    it "generates signature for SuperNode with block" do
      code = <<~RUBY
        class Child < Parent
          def method
            super(arg) { |x| x }
          end
        end
      RUBY

      analysis = described_class.new(code)
      class_node = analysis.statements.first
      method_node = class_node.body.body.first
      super_node = method_node.body.body.first

      sig = analysis.send(:compute_node_signature, super_node)
      expect(sig).to eq([:super, :with_block])
    end

    it "generates signature for ForwardingSuperNode with block" do
      code = <<~RUBY
        class Child < Parent
          def method
            super { |x| x }
          end
        end
      RUBY

      analysis = described_class.new(code)
      class_node = analysis.statements.first
      method_node = class_node.body.body.first
      super_node = method_node.body.body.first

      sig = analysis.send(:compute_node_signature, super_node)
      expect(sig).to eq([:forwarding_super, :with_block])
    end

    it "generates signature for SuperNode without block" do
      code = <<~RUBY
        class Child < Parent
          def method
            super(arg)
          end
        end
      RUBY

      analysis = described_class.new(code)
      class_node = analysis.statements.first
      method_node = class_node.body.body.first
      super_node = method_node.body.body.first

      sig = analysis.send(:compute_node_signature, super_node)
      expect(sig).to eq([:super, :no_block])
    end

    it "generates signature for ForwardingSuperNode" do
      code = <<~RUBY
        class Child < Parent
          def method(...)
            super
          end
        end
      RUBY

      analysis = described_class.new(code)
      class_node = analysis.statements.first
      method_node = class_node.body.body.first
      super_node = method_node.body.body.first

      sig = analysis.send(:compute_node_signature, super_node)
      expect(sig).to eq([:forwarding_super, :no_block])
    end

    it "generates signature for LambdaNode with parameters" do
      code = <<~RUBY
        my_lambda = ->(x, y) { x + y }
      RUBY

      analysis = described_class.new(code)
      # The lambda is inside the assignment
      assign_node = analysis.statements.first
      lambda_node = assign_node.value

      sig = analysis.send(:compute_node_signature, lambda_node)
      expect(sig.first).to eq(:lambda)
      expect(sig.last).to include("x")
    end

    it "generates signature for LambdaNode without parameters" do
      code = <<~RUBY
        my_lambda = -> { 42 }
      RUBY

      analysis = described_class.new(code)
      assign_node = analysis.statements.first
      lambda_node = assign_node.value

      sig = analysis.send(:compute_node_signature, lambda_node)
      expect(sig).to eq([:lambda, ""])
    end

    it "generates signature for PreExecutionNode (BEGIN block)" do
      code = <<~RUBY
        BEGIN { puts "startup" }
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig.first).to eq(:pre_execution)
      expect(sig.last).to eq(1) # line number
    end

    it "generates signature for PostExecutionNode (END block)" do
      code = <<~RUBY
        END { puts "cleanup" }
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig.first).to eq(:post_execution)
      expect(sig.last).to eq(1) # line number
    end

    it "generates signature for ParenthesesNode" do
      code = <<~RUBY
        (complex_expression + other)
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig.first).to eq(:parens)
    end

    it "generates fallback signature for unknown node types" do
      # Use a node type that doesn't have explicit handling
      code = <<~RUBY
        alias new_name old_name
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig.first).to eq(:other)
    end

    it "extracts symbol arguments from CallNode" do
      code = <<~RUBY
        method_call(:symbol_arg)
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:call, :method_call, :symbol_arg])
    end
  end

  describe "#attach_comments_safely!" do
    # This tests line 149-154 (JRuby compatibility path)
    # We can't easily test the JRuby path on MRI, but we can verify the normal path works

    it "attaches comments successfully on standard Ruby" do
      code = <<~RUBY
        # Comment
        def foo; end
      RUBY

      # Should not raise
      analysis = described_class.new(code)
      expect(analysis.valid?).to be true
    end
  end

  describe "#extract_and_integrate_all_nodes" do
    # Tests lines 163-169 for edge cases

    it "handles nil body from parse result" do
      # Empty file
      analysis = described_class.new("")
      expect(analysis.statements).to eq([])
    end

    it "handles single statement (non-StatementsNode body)" do
      # A file with just an expression
      code = "42"
      analysis = described_class.new(code)
      expect(analysis.statements).not_to be_empty
    end
  end
end
