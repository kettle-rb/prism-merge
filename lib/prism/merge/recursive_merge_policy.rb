# frozen_string_literal: true

module Prism
  module Merge
    class RecursiveMergePolicy
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def should_merge?(template_node:, dest_node:)
        return false unless template_node && dest_node
        return false if merger.instance_variable_get(:@current_depth) >= merger.max_recursion_depth

        actual_template = unwrap_node(template_node)
        actual_dest = unwrap_node(dest_node)
        return false unless actual_template.class == actual_dest.class
        return false unless multiline_wrapper?(actual_template) && multiline_wrapper?(actual_dest)

        case actual_template
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          true
        when Prism::CallNode
          return false unless actual_template.block && actual_dest.block

          template_body = actual_template.block.body
          dest_body = actual_dest.block.body

          body_has_mergeable_statements?(template_body) && body_has_mergeable_statements?(dest_body)
        when Prism::BeginNode
          !!(merger.send(:begin_node_has_clause_or_body?, actual_template) && merger.send(:begin_node_has_clause_or_body?, actual_dest))
        else
          false
        end
      end

      def body_has_mergeable_statements?(body)
        return false unless body.is_a?(Prism::StatementsNode)
        return false if body.body.empty?

        body.body.any? { |statement| mergeable_statement?(statement) }
      end

      def mergeable_statement?(node)
        case node
        when Prism::CallNode, Prism::DefNode, Prism::ClassNode, Prism::ModuleNode,
             Prism::SingletonClassNode, Prism::ConstantWriteNode, Prism::ConstantPathWriteNode,
             Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode,
             Prism::ClassVariableWriteNode, Prism::GlobalVariableWriteNode,
             Prism::MultiWriteNode, Prism::IfNode, Prism::UnlessNode, Prism::CaseNode,
             Prism::BeginNode
          true
        else
          false
        end
      end

      private

      def unwrap_node(node)
        node.respond_to?(:unwrap) ? node.unwrap : node
      end

      def multiline_wrapper?(node)
        node.location.start_line < node.location.end_line
      end
    end
  end
end
