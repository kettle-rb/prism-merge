# frozen_string_literal: true

module Prism
  module Merge
    # Thin navigable adapter for top-level Prism statements used by
    # PartialTemplateMerger.
    #
    # The shared navigable substrate expects statement-like objects that expose
    # `type`, `text`, and `source_position`. Prism::Merge::FileAnalysis returns
    # raw Prism nodes (and wrapped frozen nodes) whose native API is richer than
    # that contract but not shaped the same way. This adapter keeps the partial
    # merger thin without changing the full SmartMerger path.
    class PartialTemplateNode
      attr_reader :node

      def initialize(node)
        @node = node
      end

      def type
        case inner_node
        when ::Prism::ClassNode
          :class
        when ::Prism::ModuleNode
          :module
        when ::Prism::DefNode
          :def
        when ::Prism::SingletonClassNode
          :singleton_class
        when ::Prism::ConstantWriteNode, ::Prism::ConstantPathWriteNode
          :const
        when ::Prism::CallNode
          inner_node.block ? :call_with_block : :call
        when ::Prism::MultiWriteNode
          :multi_write
        when ::Prism::LocalVariableWriteNode
          :local_var
        when ::Prism::InstanceVariableWriteNode
          :ivar
        when ::Prism::ClassVariableWriteNode
          :cvar
        when ::Prism::GlobalVariableWriteNode
          :gvar
        when ::Prism::IfNode
          :if
        when ::Prism::UnlessNode
          :unless
        when ::Prism::CaseNode
          :case
        when ::Prism::CaseMatchNode
          :case_match
        when ::Prism::WhileNode
          :while
        when ::Prism::UntilNode
          :until
        when ::Prism::ForNode
          :for
        when ::Prism::BeginNode
          :begin
        when ::Prism::LambdaNode
          :lambda
        when ::Prism::PreExecutionNode
          :pre_execution
        when ::Prism::PostExecutionNode
          :post_execution
        else
          fallback_type_name
        end
      end

      def text
        node.slice.to_s
      end

      def source_position
        loc = node.location
        return unless loc

        {
          start_line: loc.start_line,
          end_line: loc.end_line,
        }
      end

      def start_line
        source_position&.dig(:start_line)
      end

      def end_line
        source_position&.dig(:end_line)
      end

      def location
        node.location
      end

      def inner_node
        node.respond_to?(:unwrap) ? node.unwrap : node
      end

      def method_missing(method_name, *args, &block)
        return node.public_send(method_name, *args, &block) if node.respond_to?(method_name)

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        node.respond_to?(method_name, include_private) || super
      end

      private

      def fallback_type_name
        class_name = inner_node.class.name.to_s.split("::").last
        class_name.sub(/Node\z/, "").gsub(/([a-z\d])([A-Z])/, "\\1_\\2").downcase.to_sym
      end
    end
  end
end
