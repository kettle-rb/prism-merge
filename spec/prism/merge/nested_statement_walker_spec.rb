# frozen_string_literal: true

RSpec.describe Prism::Merge::NestedStatementWalker do
  def parse_statements(source)
    Prism.parse(source).value.statements
  end

  def literal_value(node)
    node.respond_to?(:unescaped) ? node.unescaped : node.slice
  end

  describe ".walk" do
    it "recursively yields statements inside blocks and conditional branches" do
      source = <<~RUBY
        platform :mri do
          gem "native"
          if ENV["CI"]
            gem "ci"
          else
            gem "prod"
          end
        end

        gem "top"
      RUBY

      gem_names = described_class.walk(parse_statements(source)).filter_map do |node|
        next unless node.is_a?(Prism::CallNode) && node.name == :gem

        literal_value(node.arguments.arguments.first)
      end

      expect(gem_names).to eq(["native", "ci", "prod", "top"])
    end
  end

  describe ".walk_with_context" do
    let(:next_context) do
      lambda do |node:, current_context:, **|
        case node
        when Prism::CallNode
          arg = node.arguments&.arguments&.first
          rendered_arg = if arg.is_a?(Prism::SymbolNode)
            ":#{literal_value(arg)}"
          else
            literal_value(arg).inspect
          end
          current_context + ["#{node.name}(#{rendered_arg})"]
        when Prism::IfNode
          current_context + ["if #{node.predicate.slice.strip}"]
        when Prism::UnlessNode
          current_context + ["unless #{node.predicate.slice.strip}"]
        else
          current_context
        end
      end
    end

    it "propagates caller-defined context through nested block and conditional recursion" do
      source = <<~RUBY
        platform :mri do
          gem "native"
          unless ENV["SKIP"]
            gem "allowed"
          end
        end

        gem "top"
      RUBY

      contexts_by_gem = {}

      described_class.walk_with_context(
        parse_statements(source),
        context_stack: [],
        next_context: next_context,
      ) do |node, context_stack|
        next unless node.is_a?(Prism::CallNode) && node.name == :gem

        gem_name = literal_value(node.arguments.arguments.first)
        contexts_by_gem[gem_name] = context_stack.join(" > ")
      end

      expect(contexts_by_gem).to eq(
        "native" => "platform(:mri)",
        "allowed" => "platform(:mri) > unless ENV[\"SKIP\"]",
        "top" => "",
      )
    end
  end
end
