# frozen_string_literal: true

require "prism/merge"

RSpec.describe Prism::Merge::PartialTemplateNode, :prism_backend do
  before do
    stub_const("Location", Struct.new(:start_line, :end_line))
    stub_const("PlainNode", Struct.new(:slice, :location, :custom_value))
    stub_const("WrappedNode", Struct.new(:inner) do
      def unwrap
        inner
      end

      def slice
        inner.slice
      end

      def location
        inner.location
      end
    end)
  end

  def parse_first(code)
    Prism.parse(code).value.statements.body.first
  end

  def wrapped_type_for(code)
    described_class.new(parse_first(code)).type
  end

  describe "#type" do
    it "maps common prism node classes onto stable navigable type names", :aggregate_failures do
      expect(wrapped_type_for("class Example\nend\n")).to eq(:class)
      expect(wrapped_type_for("module Example\nend\n")).to eq(:module)
      expect(wrapped_type_for("def example\nend\n")).to eq(:def)
      expect(wrapped_type_for("foo\n")).to eq(:call)
      expect(wrapped_type_for("foo do\nend\n")).to eq(:call_with_block)
      expect(wrapped_type_for("VALUE = 1\n")).to eq(:const)
      expect(wrapped_type_for("Foo::VALUE = 1\n")).to eq(:const)
      expect(wrapped_type_for("value = 1\n")).to eq(:local_var)
      expect(wrapped_type_for("@value = 1\n")).to eq(:ivar)
      expect(wrapped_type_for("@@value = 1\n")).to eq(:cvar)
      expect(wrapped_type_for("$value = 1\n")).to eq(:gvar)
      expect(wrapped_type_for("if true\n  :ok\nend\n")).to eq(:if)
      expect(wrapped_type_for("unless false\n  :ok\nend\n")).to eq(:unless)
      expect(wrapped_type_for("case value\nwhen 1\n  :ok\nend\n")).to eq(:case)
      expect(wrapped_type_for("while false\n  break\nend\n")).to eq(:while)
      expect(wrapped_type_for("until true\n  break\nend\n")).to eq(:until)
      expect(wrapped_type_for("begin\n  :ok\nend\n")).to eq(:begin)
      expect(wrapped_type_for("for item in [1]\n  item\nend\n")).to eq(:for)
      expect(wrapped_type_for("-> { :ok }\n")).to eq(:lambda)
      expect(wrapped_type_for("BEGIN { :ok }\n")).to eq(:pre_execution)
      expect(wrapped_type_for("END { :ok }\n")).to eq(:post_execution)
    end

    it "falls back to a snake-cased class name for non-prism node types" do
      node = PlainNode.new("custom", Location.new(1, 1), :value)
      wrapped = described_class.new(node)

      expect(wrapped.type).to eq(:plain)
    end

    it "inspects the unwrapped node when a wrapper responds to #unwrap" do
      wrapped = WrappedNode.new(parse_first("class Example\nend\n"))

      expect(described_class.new(wrapped).type).to eq(:class)
    end
  end

  describe "delegation helpers" do
    it "exposes slice-backed text and source positions" do
      node = described_class.new(parse_first("class Example\nend\n"))

      expect(node.text).to include("class Example")
      expect(node.source_position).to eq({start_line: 1, end_line: 2})
      expect(node.start_line).to eq(1)
      expect(node.end_line).to eq(2)
    end

    it "delegates unknown methods to the wrapped node" do
      node = described_class.new(PlainNode.new("custom", Location.new(3, 3), :value))

      expect(node.custom_value).to eq(:value)
      expect(node).to respond_to(:custom_value)
    end

    it "returns nil source_position when the wrapped node has no location" do
      node = described_class.new(PlainNode.new("custom", nil, :value))

      expect(node.source_position).to be_nil
      expect(node.start_line).to be_nil
      expect(node.end_line).to be_nil
    end
  end
end
