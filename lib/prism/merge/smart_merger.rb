# frozen_string_literal: true

module Prism
  module Merge
    # Orchestrates the smart merge process using FileAnalysis, FileAligner,
    # ConflictResolver, and MergeResult to merge two Ruby files intelligently.
    class SmartMerger
      attr_reader :template_analysis, :dest_analysis, :aligner, :resolver, :result

      # @param template_content [String] Template Ruby source
      # @param dest_content [String] Destination Ruby source
      # @param signature_generator [Proc, nil] Optional proc to generate node signatures
      def initialize(template_content, dest_content, signature_generator: nil)
        @template_content = template_content
        @dest_content = dest_content
        @template_analysis = FileAnalysis.new(template_content, signature_generator: signature_generator)
        @dest_analysis = FileAnalysis.new(dest_content, signature_generator: signature_generator)
        @aligner = FileAligner.new(@template_analysis, @dest_analysis)
        @resolver = ConflictResolver.new(@template_analysis, @dest_analysis)
        @result = MergeResult.new
      end

      # Perform the merge
      # @return [String] Merged content
      def merge
        # Handle invalid files
        unless @template_analysis.valid?
          raise Prism::Merge::TemplateParseError.new(
            "Template file has parsing errors",
            content: @template_content,
            parse_result: @template_analysis.parse_result,
          )
        end

        unless @dest_analysis.valid?
          raise Prism::Merge::DestinationParseError.new(
            "Destination file has parsing errors",
            content: @dest_content,
            parse_result: @dest_analysis.parse_result,
          )
        end

        # Find anchors and boundaries
        boundaries = @aligner.align

        # Process the merge by walking through anchors and boundaries in order
        process_merge(boundaries)

        # Return final content
        @result.to_s
      end

      # Merge with debug output
      # @return [Hash] Hash with :content and :debug keys
      def merge_with_debug
        content = merge
        {
          content: content,
          debug: @result.debug_output,
          statistics: @result.statistics,
        }
      end

      private

      def process_merge(boundaries)
        # Build complete timeline of anchors and boundaries
        timeline = build_timeline(boundaries)

        timeline.each do |item|
          if item[:type] == :anchor
            process_anchor(item[:anchor])
          else
            process_boundary(item[:boundary])
          end
        end
      end

      def build_timeline(boundaries)
        timeline = []

        # Add all anchors and boundaries sorted by position
        @aligner.anchors.each do |anchor|
          timeline << {type: :anchor, anchor: anchor, sort_key: [anchor.template_start, 0]}
        end

        boundaries.each do |boundary|
          # Sort boundaries by their starting position
          t_start = boundary.template_range&.begin || 0
          d_start = boundary.dest_range&.begin || 0
          sort_key = [t_start, d_start, 1] # 1 ensures boundaries come after anchors at same position

          timeline << {type: :boundary, boundary: boundary, sort_key: sort_key}
        end

        timeline.sort_by! { |item| item[:sort_key] }
        timeline
      end

      def process_anchor(anchor)
        # Anchors represent identical or equivalent sections - just copy them
        case anchor.match_type
        when :freeze_block
          # Freeze blocks from destination take precedence
          add_freeze_block_from_dest(anchor)
        when :signature_match
          # For signature matches (same structure, different content), prefer destination
          add_signature_match_from_dest(anchor)
        when :exact_match
          # For exact matches, prefer template (it's the source of truth)
          add_exact_match_from_template(anchor)
        else
          # Unknown match type - default to template
          add_exact_match_from_template(anchor)
        end
      end

      def add_freeze_block_from_dest(anchor)
        anchor.dest_range.each do |line_num|
          line = @dest_analysis.line_at(line_num)
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_FREEZE_BLOCK,
            dest_line: line_num,
          )
        end
      end

      def add_signature_match_from_dest(anchor)
        # For signature matches, use destination version (has customizations)
        anchor.dest_range.each do |line_num|
          line = @dest_analysis.line_at(line_num)
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_REPLACED,
            dest_line: line_num,
          )
        end
      end

      def add_exact_match_from_template(anchor)
        anchor.template_range.each do |line_num|
          line = @template_analysis.line_at(line_num)
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_KEPT_TEMPLATE,
            template_line: line_num,
          )
        end
      end

      def process_boundary(boundary)
        @resolver.resolve(boundary, @result)
      end
    end
  end
end
