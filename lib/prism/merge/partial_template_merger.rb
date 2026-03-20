# frozen_string_literal: true

module Prism
  module Merge
    # Merges a partial Ruby template into a specific top-level structural section
    # of a destination document.
    #
    # This implementation uses the shared navigable partial-template substrate in
    # `ast-merge` and keeps Ruby-specific behavior local: top-level Prism
    # statement adaptation, section-boundary selection, and SmartMerger wiring.
    class PartialTemplateMerger < ::Ast::Merge::PartialTemplateMergerBase
      protected

      def create_analysis(content)
        FileAnalysis.new(content)
      end

      def navigable_statements_for(analysis)
        Array(analysis.statements).map { |node| PartialTemplateNode.new(node) }
      end

      def create_smart_merger(template_content, destination_content)
        SmartMerger.new(
          template_content,
          destination_content,
          preference: preference,
          add_template_only_nodes: add_missing,
          freeze_token: FileAnalysis::DEFAULT_FREEZE_TOKEN,
          match_refiner: match_refiner,
          node_typing: node_typing,
          signature_generator: signature_generator,
        )
      end

      def find_section_end(statements, injection_point)
        return injection_point.anchor.index unless injection_point.boundary

        injection_point.boundary.index - 1
      end

      def node_to_text(node, analysis = nil)
        pos = if node.respond_to?(:source_position)
          node.source_position
        elsif node.respond_to?(:location) && node.location
          {
            start_line: node.location.start_line,
            end_line: node.location.end_line,
          }
        end
        return node.text.to_s unless analysis&.respond_to?(:source) && pos

        analysis.source.lines[(pos[:start_line] - 1)..(pos[:end_line] - 1)].join
      end
    end
  end
end
