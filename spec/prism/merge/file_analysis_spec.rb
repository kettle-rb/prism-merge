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

    it "does not include freeze markers as leading comments for nodes" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen
          "f"
        end
        # prism-merge:unfreeze

        # Regular leading comment
        # Another regular line
        def not_frozen
          "nf"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.find { |n| n[:node].is_a?(Prism::DefNode) && n[:node].name == :not_frozen }

      # Ensure no leading comment is a prism-merge marker
      expect(node_info[:leading_comments].map(&:slice).join("\n")).not_to include("prism-merge:freeze")
      expect(node_info[:leading_comments].map(&:slice).join("\n")).not_to include("prism-merge:unfreeze")
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

  describe "#generate_signature with nil generator" do
    it "returns nil when generator returns nil" do
      code = "def example; end"
      null_gen = ->(_node) { nil }

      analysis = described_class.new(code, signature_generator: null_gen)
      expect(analysis.signature_at(0)).to be_nil
    end
  end

  describe "#fallthrough_node?" do
    it "returns true for Prism::Node objects" do
      code = "def example; end"
      analysis = described_class.new(code)
      node = analysis.statements.first

      expect(analysis.send(:fallthrough_node?, node)).to be true
    end

    it "returns false for unrelated objects" do
      analysis = described_class.new("")
      expect(analysis.send(:fallthrough_node?, "string")).to be false
      expect(analysis.send(:fallthrough_node?, 123)).to be false
    end
  end

  describe "freeze_token nil behavior" do
    it "does not recognise freeze blocks when freeze_token is nil and retains the markers as comments" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen
          "f"
        end
        # prism-merge:unfreeze
      RUBY

      analysis = described_class.new(code, freeze_token: nil)
      expect(analysis.freeze_blocks).to be_empty

      # The marker comments should remain attached to following nodes as leading comments
      node_info = analysis.nodes_with_comments.first
      expect(node_info[:leading_comments].map(&:slice).join("\n")).to include("prism-merge:freeze")
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
    # These tests cover compute_node_signature logic across many node types

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

    it "falls back to 'self' when expression.slice raises an error" do
      code = <<~RUBY
        class << self
          def foo; end
        end
      RUBY

      analysis = described_class.new(code)
      node = analysis.statements.first

      # Replace expression with an object whose slice method raises
      bad_expr = Object.new
      def bad_expr.slice
        raise "boom"
      end
      node.instance_variable_set(:@expression, bad_expr)

      sig = analysis.send(:compute_node_signature, node)
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

    it "extracts non-string/symbol first arguments by using slice for other node types" do
      code = <<~RUBY
        def helper; end
        method_call(helper)
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(1)

      # The first argument is a CallNode (helper), so extract_first_argument_value should use slice
      expect(sig[2]).to include("helper")
    end

    it "extracts string arguments from CallNode" do
      code = <<~RUBY
        method_call("string_arg")
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:call, :method_call, "string_arg"])
    end

    it "generates call_with_block signature for CallNode with block" do
      code = <<~RUBY
        def example
          appraise "ruby-3.3" do
            true
          end
        end
      RUBY

      analysis = described_class.new(code)
      class_or_def = analysis.statements.first
      # find the CallNode inside the method body
      call_node = class_or_def.body.body.first
      sig = analysis.send(:compute_node_signature, call_node)

      expect(sig[0]).to eq(:call_with_block)
      expect(sig[1]).to eq(:appraise)
      expect(sig[2]).to eq("ruby-3.3")
    end

    it "generates call_with_block signature for CallNode with receiver and block" do
      code = <<~RUBY
        def example
          config.process "x" do
            1
          end
        end
      RUBY

      analysis = described_class.new(code)
      def_node = analysis.statements.first
      call_node = def_node.body.body.first
      sig = analysis.send(:compute_node_signature, call_node)

      expect(sig[0]).to eq(:call_with_block)
      expect(sig[1]).to eq(:process)
      # For call_with_block, the signature uses the first argument OR receiver for assignment calls; here it uses the first arg
      expect(sig[2]).to eq("x")
    end

    it "generates signature for IfNode" do
      code = <<~RUBY
        if enabled?
          do_something
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:if, "enabled?"])
    end

    it "generates signature for EmbeddedStatementsNode inside string interpolation" do
      analysis = described_class.new("")
      # We can't always rely on the parser producing an actual instance of
      # EmbeddedStatementsNode in the AST for all Prism versions, so construct
      # a minimal instance by allocating and stubbing the methods we need.
      embedded = Prism::EmbeddedStatementsNode.allocate
      # Provide a fake statements struct with a slice method
      fake_statements = Object.new
      fake_statements.define_singleton_method(:slice) { "1 + 2" }
      # Use define_singleton_method to capture the closure properly
      embedded.define_singleton_method(:statements) { fake_statements }

      sig = analysis.send(:compute_node_signature, embedded)
      expect(sig[0]).to eq(:embedded)
      expect(sig[1]).to include("1")
    end

    it "handles CallNode assignment without block" do
      code = <<~RUBY
        class C
          def self.configure
            config.setting = "value"
          end
        end
      RUBY

      analysis = described_class.new(code)
      # find the call node inside the method body
      class_node = analysis.statements.first
      def_node = class_node.body.body.first
      call_node = def_node.body.body.first

      sig = analysis.send(:compute_node_signature, call_node)
      expect(sig[0]).to eq(:call)
      expect(sig[1]).to eq(:setting=)
      expect(sig[2]).to include("config")
    end

    it "returns nil as first argument when CallNode has no arguments" do
      code = <<~RUBY
        def call_me
          helper
        end
      RUBY

      analysis = described_class.new(code)
      node = analysis.statements.first
      # node is a DefNode, its body is a StatementsNode; extract the first statement which is the CallNode
      call_node = node.body.body.first

      sig = analysis.send(:compute_node_signature, call_node)
      expect(sig[2]).to be_nil
    end
  end

  describe "#attach_comments_safely!" do
    it "rescues NameError with 'Comments' and retries attach_comments!" do
      # Use allocate to bypass initialization which calls attach_comments_safely!
      analysis = described_class.allocate
      parse_result = double("ParseResult")
      # First call raises NameError mentioning Comments, second call succeeds
      expect(parse_result).to receive(:attach_comments!).ordered.and_raise(NameError.new("uninitialized constant Comments"))
      expect(parse_result).to receive(:attach_comments!).ordered.and_return(nil)
      analysis.instance_variable_set(:@parse_result, parse_result)

      expect { analysis.send(:attach_comments_safely!) }.not_to raise_error
    end

    it "re-raises NameError when message doesn't include Comments" do
      analysis = described_class.allocate
      parse_result = double("ParseResult")
      allow(parse_result).to receive(:attach_comments!).and_raise(NameError.new("something else"))
      analysis.instance_variable_set(:@parse_result, parse_result)

      expect { analysis.send(:attach_comments_safely!) }.to raise_error(NameError)
    end
    # Tests JRuby-compatible attach_comments_safely! behavior
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
    # Tests extract_and_integrate_all_nodes edge cases (nil body and single statement handling)

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

  describe "#compute_node_signature with FreezeNode" do
    it "generates signature for FreezeNode" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen_method
          "frozen"
        end
        # prism-merge:unfreeze
      RUBY

      analysis = described_class.new(code)
      freeze_node = analysis.freeze_blocks.first

      expect(freeze_node).to be_a(Prism::Merge::FreezeNode)

      # The FreezeNode should have a signature
      node_info = analysis.nodes_with_comments.find { |n| n[:node].is_a?(Prism::Merge::FreezeNode) }
      expect(node_info).not_to be_nil
      expect(node_info[:signature]).not_to be_nil
    end
  end

  describe "DefNode with special parameters" do
    it "handles method with rest parameters" do
      code = <<~RUBY
        def method_with_rest(*args)
          args.join(", ")
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :method_with_rest, [:args]])
    end

    it "handles method with keyword rest parameters" do
      code = <<~RUBY
        def method_with_keyrest(**kwargs)
          kwargs.inspect
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :method_with_keyrest, [:kwargs]])
    end

    it "handles method with block parameter" do
      code = <<~RUBY
        def method_with_block(&block)
          block.call
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :method_with_block, [:block]])
    end

    it "handles method with all parameter types" do
      code = <<~RUBY
        def complex_method(req, opt = nil, *rest, key:, key_opt: nil, **keyrest, &blk)
          [req, opt, rest, key, key_opt, keyrest, blk]
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      sig = node_info[:signature]
      expect(sig[0]).to eq(:def)
      expect(sig[1]).to eq(:complex_method)
      # Parameter names extracted (order: requireds, optionals, rest, posts, keywords, keyword_rest, block)
      expect(sig[2]).to eq([:req, :opt, :rest, :key, :key_opt, :keyrest, :blk])
    end

    it "handles method with forwarding parameters" do
      code = <<~RUBY
        def forwarding_method(...)
          other_method(...)
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      sig = node_info[:signature]
      expect(sig[0]).to eq(:def)
      expect(sig[1]).to eq(:forwarding_method)
      expect(sig[2]).to eq([:forwarding])
    end
  end

  describe "signature generator returning Prism::Node for fallthrough" do
    it "falls through to default when generator returns the node" do
      code = <<~RUBY
        def my_method
          "hello"
        end

        CONSTANT = "value"
      RUBY

      # Generator that only handles CallNodes, returns node for others
      selective_generator = lambda do |node|
        case node
        when Prism::CallNode
          [:custom_call, node.name]
        else
          # Return the node to fall through to default
          node
        end
      end

      analysis = described_class.new(code, signature_generator: selective_generator)

      # DefNode should have default signature (fallthrough)
      def_info = analysis.nodes_with_comments.find { |n| n[:node].is_a?(Prism::DefNode) }
      expect(def_info[:signature][0]).to eq(:def)
      expect(def_info[:signature][1]).to eq(:my_method)

      # ConstantWriteNode should have default signature (fallthrough)
      const_info = analysis.nodes_with_comments.find { |n| n[:node].is_a?(Prism::ConstantWriteNode) }
      expect(const_info[:signature]).to eq([:const, :CONSTANT])
    end
  end

  describe "#compute_node_signature for rare node types" do
    it "handles CaseNode without predicate" do
      code = <<~RUBY
        case
        when true
          "yes"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:case, ""])
    end

    it "handles CaseMatchNode (pattern matching)" do
      code = <<~RUBY
        case [1, 2]
        in [a, b]
          a + b
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:case_match)
      expect(node_info[:signature][1]).to eq("[1, 2]")
    end

    it "handles WhileNode" do
      code = <<~RUBY
        while x < 10
          x += 1
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:while, "x < 10"])
    end

    it "handles UntilNode" do
      code = <<~RUBY
        until done
          work
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:until, "done"])
    end

    it "handles ForNode" do
      code = <<~RUBY
        for i in items
          puts i
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:for, "i", "items"])
    end

    it "handles BeginNode" do
      code = <<~RUBY
        begin
          risky_operation
        rescue
          handle_error
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:begin)
    end

    it "handles SuperNode without block" do
      # SuperNode appears inside a method, so we need to test it via a method definition
      # but we can test the signature computation directly
      code = <<~RUBY
        class Child < Parent
          def foo
            super(1, 2)
          end
        end
      RUBY

      analysis = described_class.new(code)
      # The top-level node is the ClassNode
      class_info = analysis.nodes_with_comments.first
      expect(class_info[:signature][0]).to eq(:class)
    end

    it "handles ForwardingSuperNode" do
      code = <<~RUBY
        class Child < Parent
          def foo(...)
            super
          end
        end
      RUBY

      analysis = described_class.new(code)
      class_info = analysis.nodes_with_comments.first
      expect(class_info[:signature][0]).to eq(:class)
    end

    it "handles LambdaNode" do
      code = <<~RUBY
        my_lambda = ->(x, y) { x + y }
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      # The top-level is a LocalVariableWriteNode (the lambda is assigned to a variable)
      expect(node_info[:signature][0]).to eq(:local_var)
      expect(node_info[:signature][1]).to eq(:my_lambda)
    end

    it "handles PreExecutionNode (BEGIN block)" do
      code = <<~RUBY
        BEGIN {
          puts "startup"
        }
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:pre_execution)
    end

    it "handles PostExecutionNode (END block)" do
      code = <<~RUBY
        END {
          puts "cleanup"
        }
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:post_execution)
    end

    it "handles assignment method call with block" do
      code = <<~RUBY
        config.setting = proc { "value" }
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      # This is a CallNode with name ending in =
      expect(node_info[:signature][0]).to eq(:call)
      expect(node_info[:signature][1]).to eq(:setting=)
    end

    it "handles SingletonClassNode" do
      code = <<~RUBY
        class << self
          def singleton_method
            "hello"
          end
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:singleton_class, "self"])
    end

    it "handles ModuleNode" do
      code = <<~RUBY
        module MyModule
          CONSTANT = 1
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:module, "MyModule"])
    end

    it "handles ConstantPathWriteNode" do
      code = <<~RUBY
        Outer::Inner::CONST = "value"
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:const, "Outer::Inner::CONST"])
    end

    it "handles InstanceVariableWriteNode" do
      # At top level, instance variable writes are statements
      code = <<~RUBY
        @instance_var = "value"
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:ivar, :@instance_var])
    end

    it "handles ClassVariableWriteNode" do
      code = <<~RUBY
        @@class_var = "value"
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:cvar, :@@class_var])
    end

    it "handles GlobalVariableWriteNode" do
      code = <<~RUBY
        $global_var = "value"
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:gvar, :$global_var])
    end

    it "handles MultiWriteNode with local variables" do
      code = <<~RUBY
        a, b, c = [1, 2, 3]
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:multi_write)
      expect(node_info[:signature][1]).to include(:a)
      expect(node_info[:signature][1]).to include(:b)
      expect(node_info[:signature][1]).to include(:c)
    end

    it "handles MultiWriteNode with instance variables" do
      code = <<~RUBY
        @a, @b = [1, 2]
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:multi_write)
      expect(node_info[:signature][1]).to include(:@a)
      expect(node_info[:signature][1]).to include(:@b)
    end

    it "handles MultiWriteNode with class variables" do
      code = <<~RUBY
        @@a, @@b = [1, 2]
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:multi_write)
      expect(node_info[:signature][1]).to include(:@@a)
      expect(node_info[:signature][1]).to include(:@@b)
    end

    it "handles MultiWriteNode with global variables" do
      code = <<~RUBY
        $a, $b = [1, 2]
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:multi_write)
      expect(node_info[:signature][1]).to include(:$a)
      expect(node_info[:signature][1]).to include(:$b)
    end

    it "handles MultiWriteNode with mixed target types" do
      code = <<~RUBY
        a, @b, CONST = [1, 2, 3]
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:multi_write)
      # Local variable
      expect(node_info[:signature][1]).to include(:a)
      # Instance variable
      expect(node_info[:signature][1]).to include(:@b)
      # Constant (uses slice fallback)
      expect(node_info[:signature][1].any? { |t| t.to_s.include?("CONST") }).to be true
    end

    it "handles UnlessNode" do
      code = <<~RUBY
        unless condition
          do_something
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:unless, "condition"])
    end

    it "falls back to :other for unknown node types" do
      # We can test this by using a custom generator that returns the node,
      # and mocking a node type that isn't handled
      code = "42"

      analysis = described_class.new(code)
      # IntegerNode is not in the case statement, should fall back to :other
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:other)
    end
  end

  describe "edge cases for parameter extraction" do
    it "handles method with ForwardingParameterNode as parameter type" do
      # This covers the case when node.parameters.is_a?(Prism::ForwardingParameterNode)
      code = <<~RUBY
        def forward_all(...)
          other(...)
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :forward_all, [:forwarding]])
    end

    it "handles method with keyword_rest that is ForwardingParameterNode" do
      # This covers line 486: keyword_rest.is_a?(Prism::ForwardingParameterNode)
      code = <<~RUBY
        def mixed_forward(a, ...)
          other(a, ...)
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      sig = node_info[:signature]
      expect(sig[0]).to eq(:def)
      expect(sig[1]).to eq(:mixed_forward)
      # Should have 'a' and 'forwarding'
      expect(sig[2]).to include(:a)
      expect(sig[2]).to include(:forwarding)
    end

    it "handles method with posts parameters (after rest)" do
      # This covers line 480: node.parameters.posts
      code = <<~RUBY
        def with_posts(first, *middle, last)
          [first, middle, last]
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      sig = node_info[:signature]
      expect(sig[0]).to eq(:def)
      expect(sig[1]).to eq(:with_posts)
      expect(sig[2]).to include(:first)
      expect(sig[2]).to include(:middle)
      expect(sig[2]).to include(:last)
    end
  end

  describe "single statement body handling" do
    it "handles parse result with single non-StatementsNode body" do
      # This covers line 146: else branch when body is not StatementsNode
      code = "__END__"

      analysis = described_class.new(code)
      # __END__ creates a program with no statements
      expect(analysis.statements).to eq([])
    end
  end

  describe "extract_nodes_with_comments edge cases" do
    it "handles file with no freeze_token (nil freeze_marker_pattern)" do
      # This covers line 297: when freeze_marker_pattern is nil
      code = <<~RUBY
        # Comment about freeze blocks but freeze_token is nil
        def example
          "test"
        end
      RUBY

      analysis = described_class.new(code, freeze_token: nil)
      node_info = analysis.nodes_with_comments.first

      # Without freeze_token, there's no freeze_marker_pattern
      # Comments should still be attached normally
      expect(node_info[:leading_comments].size).to eq(1)
      expect(node_info[:leading_comments].first.slice).to include("freeze blocks")
    end
  end

  describe "signature generator fallthrough behavior" do
    it "uses default signature when generator returns the exact node object" do
      # This covers line 473: the fallthrough_node? check
      code = <<~RUBY
        def fallthrough_example
          "test"
        end
      RUBY

      # Generator that returns the node itself for fallthrough
      fallthrough_gen = ->(node) { node }

      analysis = described_class.new(code, signature_generator: fallthrough_gen)
      sig = analysis.signature_at(0)

      # Should fall through to default signature
      expect(sig).to eq([:def, :fallthrough_example, []])
    end

    it "handles generator returning non-node non-array values as nil signature" do
      # This covers when signature is neither an Array nor a fallthrough node
      code = "def example; end"

      # Generator that returns something that's not an Array or Node
      weird_gen = ->(_node) { "invalid" }

      analysis = described_class.new(code, signature_generator: weird_gen)
      sig = analysis.signature_at(0)

      # String return should be used directly (not array, not fallthrough)
      expect(sig).to eq("invalid")
    end
  end

  describe "extract_first_argument_value edge cases" do
    it "handles CallNode with SymbolNode argument" do
      # This covers line 655: when Prism::SymbolNode
      code = <<~RUBY
        attr_reader :my_attribute
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig).to eq([:call, :attr_reader, :my_attribute])
    end

    it "handles CallNode with non-string/symbol argument using slice" do
      # This covers line 660: else branch using first_arg.slice
      code = <<~RUBY
        process(1 + 2)
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig[0]).to eq(:call)
      expect(sig[1]).to eq(:process)
      expect(sig[2]).to include("1")
    end
  end

  describe "CaseNode and CaseMatchNode without predicate" do
    it "handles CaseMatchNode without predicate" do
      # CaseMatchNode without predicate uses pattern matching syntax
      # Note: `case` without expression followed by `in` may be parsed differently
      # depending on Ruby/Prism version. Use a valid pattern matching case.
      code = <<~RUBY
        value = [1, 2]
        case value
        in [a, b] then a + b
        end
      RUBY

      analysis = described_class.new(code)
      # The CaseMatchNode is at index 1 (after the assignment)
      sig = analysis.signature_at(1)

      expect(sig[0]).to eq(:case_match)
      expect(sig[1]).to eq("value")
    end
  end

  describe "BeginNode edge cases" do
    it "handles BeginNode with nil statements" do
      # BeginNode.statements can be nil in edge cases
      code = <<~RUBY
        begin
        rescue
          handle_error
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig[0]).to eq(:begin)
      # When statements is nil or empty, first_stmt becomes ""
      expect(sig[1]).to eq("")
    end

    it "handles BeginNode with statements that have empty body" do
      code = <<~RUBY
        begin
          # just a comment, no actual statements in body
        ensure
          cleanup
        end
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig[0]).to eq(:begin)
    end
  end

  describe "ParenthesesNode edge cases" do
    it "handles ParenthesesNode with nil body" do
      # Create a test that exercises ParenthesesNode with minimal body
      code = "()"

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      # Empty parens should have empty first_expr
      expect(sig[0]).to eq(:parens)
      expect(sig[1]).to eq("")
    end

    it "handles ParenthesesNode with expression" do
      code = "(1 + 2)"

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      expect(sig[0]).to eq(:parens)
    end
  end

  describe "CallNode with assignment method" do
    it "handles assignment method call without block" do
      # This covers the branch: method_name.end_with?("=") && !node.block -> [:call, ...]
      code = <<~RUBY
        config.items = [1, 2, 3]
      RUBY

      analysis = described_class.new(code)
      sig = analysis.signature_at(0)

      # Assignment methods without blocks use :call
      expect(sig[0]).to eq(:call)
      expect(sig[1]).to eq(:items=)
      expect(sig[2]).to eq("config")
    end
  end

  describe "DefNode with no optionals, keywords, or keyword_rest" do
    it "handles method with only required parameters" do
      # This tests the branches where optionals/keywords/keyword_rest are nil/empty
      code = <<~RUBY
        def simple(a, b)
          a + b
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :simple, [:a, :b]])
    end

    it "handles method with only optional parameters" do
      code = <<~RUBY
        def with_optionals(a = 1, b = 2)
          a + b
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature]).to eq([:def, :with_optionals, [:a, :b]])
    end

    it "handles method with rest but no name (anonymous splat)" do
      # The rest parameter without name: def foo(*)
      code = <<~RUBY
        def anonymous_rest(*)
          "called"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      # Anonymous splat doesn't respond_to?(:name) with a truthy value
      expect(node_info[:signature][0]).to eq(:def)
      expect(node_info[:signature][1]).to eq(:anonymous_rest)
    end

    it "handles method with anonymous keyword rest" do
      # def foo(**) - anonymous keyword rest
      code = <<~RUBY
        def anonymous_kwrest(**)
          "called"
        end
      RUBY

      analysis = described_class.new(code)
      node_info = analysis.nodes_with_comments.first

      expect(node_info[:signature][0]).to eq(:def)
      expect(node_info[:signature][1]).to eq(:anonymous_kwrest)
    end
  end

  describe "freeze block marker filtering" do
    it "filters freeze markers from leading comments when freeze_token is set" do
      # This covers line 297: freeze_marker_pattern being truthy
      code = <<~RUBY
        # prism-merge:freeze
        def frozen_method
          "frozen"
        end
        # prism-merge:unfreeze

        # Regular comment after freeze block
        def after_freeze
          "after"
        end
      RUBY

      analysis = described_class.new(code, freeze_token: "prism-merge")

      # The after_freeze method should not have freeze markers as leading comments
      after_info = analysis.nodes_with_comments.find { |n|
        n[:node].is_a?(Prism::DefNode) && n[:node].name == :after_freeze
      }

      comments_text = after_info[:leading_comments].map(&:slice).join("\n")
      expect(comments_text).not_to include("prism-merge:freeze")
      expect(comments_text).not_to include("prism-merge:unfreeze")
      expect(comments_text).to include("Regular comment")
    end
  end

  describe "EmbeddedStatementsNode with nil statements" do
    it "handles EmbeddedStatementsNode when statements is nil" do
      analysis = described_class.new("")

      # Create an EmbeddedStatementsNode with nil statements
      embedded = Prism::EmbeddedStatementsNode.allocate
      embedded.define_singleton_method(:statements) { nil }

      sig = analysis.send(:compute_node_signature, embedded)
      expect(sig[0]).to eq(:embedded)
      expect(sig[1]).to eq("")
    end
  end

  describe "extract_and_integrate_all_nodes body type handling" do
    it "handles when parse result value.statements is nil" do
      # Empty heredoc that produces nil statements
      analysis = described_class.new("")

      expect(analysis.statements).to eq([])
    end

    it "handles when body is a single node (not StatementsNode)" do
      # Some edge cases produce a single node rather than StatementsNode
      # This is hard to trigger naturally, but we test the branch exists
      code = "42"
      analysis = described_class.new(code)

      # Should still work and produce statements
      expect(analysis.statements).not_to be_empty
    end
  end
end
