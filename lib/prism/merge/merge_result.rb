# frozen_string_literal: true

module Prism
  module Merge
    # Represents the merged output with bidirectional links to source lines.
    # Tracks merge decisions and provenance for validation and debugging.
    class MergeResult
      # Line was kept from template (no conflict or template preferred).
      # Used when template content is included without modification.
      DECISION_KEPT_TEMPLATE = :kept_template

      # Line was kept from destination (no conflict or destination preferred).
      # Used when destination content is included without modification.
      DECISION_KEPT_DEST = :kept_destination

      # Line was appended from destination (destination-only content).
      # Used for content that exists only in destination and is added to result.
      # Common for destination-specific customizations like extra methods or constants.
      DECISION_APPENDED = :appended

      # Line replaced matching content (signature match with preference applied).
      # Used when template and destination have nodes with same signature but
      # different content, and one version replaced the other based on preference.
      DECISION_REPLACED = :replaced

      # Line from destination freeze block (always preserved).
      # Used for content within kettle-dev:freeze markers that must be kept
      # from destination regardless of template content.
      DECISION_FREEZE_BLOCK = :freeze_block

      attr_reader :lines, :line_metadata

      def initialize
        @lines = []
        @line_metadata = []
      end

      # Add a line to the result
      # @param content [String] Line content (without newline)
      # @param decision [Symbol] How this line was decided
      # @param template_line [Integer, nil] 1-based line number from template
      # @param dest_line [Integer, nil] 1-based line number from destination
      # @param comment [String, nil] Optional note about this decision
      def add_line(content, decision:, template_line: nil, dest_line: nil, comment: nil)
        @lines << content
        @line_metadata << {
          decision: decision,
          template_line: template_line,
          dest_line: dest_line,
          comment: comment,
          result_line: @lines.length,
        }
      end

      # Add multiple lines from a source with same decision
      # @param source_lines [Array<String>] Lines to add
      # @param decision [Symbol] Merge decision
      # @param source [Symbol] :template or :destination
      # @param start_line [Integer] Starting line number in source
      # @param comment [String, nil] Optional note
      def add_lines_from(source_lines, decision:, source:, start_line:, comment: nil)
        source_lines.each_with_index do |line, idx|
          line_num = start_line + idx
          if source == :template
            add_line(line, decision: decision, template_line: line_num, comment: comment)
          else
            add_line(line, decision: decision, dest_line: line_num, comment: comment)
          end
        end
      end

      # Add a node's content with its comments
      # @param node_info [Hash] Node information from FileAnalysis
      # @param decision [Symbol] Merge decision
      # @param source [Symbol] :template or :destination
      # @param source_analysis [FileAnalysis] Source file analysis for preserving indentation
      def add_node(node_info, decision:, source:, source_analysis: nil)
        node = node_info[:node]
        start_line = node.location.start_line
        end_line = node.location.end_line

        # Add leading comments
        node_info[:leading_comments].each do |comment|
          comment_line = comment.location.start_line
          # Use source_analysis to get full line with indentation if available
          line = if source_analysis
            source_analysis.line_at(comment_line)&.chomp || comment.slice.rstrip
          else
            comment.slice.rstrip
          end
          if source == :template
            add_line(line, decision: decision, template_line: comment_line)
          else
            add_line(line, decision: decision, dest_line: comment_line)
          end
        end

        # Add node source lines
        # Use source_analysis.line_at to preserve original indentation
        if source_analysis
          # Get full lines from source to preserve indentation
          inline_comments = node_info[:inline_comments]
          (start_line..end_line).each do |line_num|
            line = source_analysis.line_at(line_num)&.chomp || ""

            # Handle inline comments on the last line
            if line_num == end_line && inline_comments.any?
              inline_text = inline_comments.map { |c| c.slice.strip }.join(" ")
              line = line.rstrip + " " + inline_text
            end

            if source == :template
              add_line(line, decision: decision, template_line: line_num)
            else
              add_line(line, decision: decision, dest_line: line_num)
            end
          end
        else
          # Fallback: use node.slice (loses leading indentation)
          node_source = node.slice
          node_lines = node_source.lines(chomp: true)

          # Handle inline comments
          inline_comments = node_info[:inline_comments]
          if inline_comments.any?
            # Inline comments are on the last line
            last_idx = node_lines.length - 1
            if last_idx >= 0
              inline_text = inline_comments.map { |c| c.slice.strip }.join(" ")
              node_lines[last_idx] = node_lines[last_idx].rstrip + " " + inline_text
            end
          end

          node_lines.each_with_index do |line, idx|
            line_num = start_line + idx
            if source == :template
              add_line(line, decision: decision, template_line: line_num)
            else
              add_line(line, decision: decision, dest_line: line_num)
            end
          end
        end
      end

      # Convert to final merged content string
      # @return [String]
      def to_s
        @lines.join("\n") + "\n"
      end

      # Get statistics about merge decisions
      # @return [Hash<Symbol, Integer>]
      def statistics
        stats = Hash.new(0)
        @line_metadata.each do |meta|
          stats[meta[:decision]] += 1
        end
        stats
      end

      # Get lines by decision type
      # @param decision [Symbol] Decision type to filter by
      # @return [Array<Hash>] Metadata for matching lines
      def lines_by_decision(decision)
        @line_metadata.select { |meta| meta[:decision] == decision }
      end

      # Debug output showing merge provenance
      # @return [String]
      def debug_output
        output = ["=== Merge Result Debug ==="]
        output << "Total lines: #{@lines.length}"
        output << "Statistics: #{statistics.inspect}"
        output << ""
        output << "Line-by-line provenance:"

        @lines.each_with_index do |line, idx|
          meta = @line_metadata[idx]
          parts = [
            "#{idx + 1}:".rjust(4),
            meta[:decision].to_s.ljust(20),
          ]

          parts << if meta[:template_line]
            "T:#{meta[:template_line]}".ljust(8)
          else
            " " * 8
          end

          parts << if meta[:dest_line]
            "D:#{meta[:dest_line]}".ljust(8)
          else
            " " * 8
          end

          parts << "| #{line[0..60]}"
          output << parts.join(" ")
        end

        output.join("\n")
      end
    end
  end
end
