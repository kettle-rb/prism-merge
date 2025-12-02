# frozen_string_literal: true

require "set"

module Prism
  module Merge
    # Identifies sequential "anchor sections" where template and destination
    # have identical or equivalent lines, defining merge boundaries.
    # Similar to diff algorithm but AST-aware.
    class FileAligner
      # Represents a section of matching lines between files
      Anchor = Struct.new(:template_start, :template_end, :dest_start, :dest_end, :match_type, :score) do
        def template_range
          template_start..template_end
        end

        def dest_range
          dest_start..dest_end
        end

        def length
          template_end - template_start + 1
        end
      end

      # Represents a boundary where files differ
      Boundary = Struct.new(:template_range, :dest_range, :prev_anchor, :next_anchor) do
        def template_lines
          return [] unless template_range
          (template_range.begin..template_range.end).to_a
        end

        def dest_lines
          return [] unless dest_range
          (dest_range.begin..dest_range.end).to_a
        end
      end

      attr_reader :template_analysis, :dest_analysis, :anchors, :boundaries

      # @param template_analysis [FileAnalysis] Template file analysis
      # @param dest_analysis [FileAnalysis] Destination file analysis
      def initialize(template_analysis, dest_analysis)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @anchors = []
        @boundaries = []
      end

      # Perform alignment and identify anchors and boundaries
      # @return [Array<Boundary>] Boundaries requiring conflict resolution
      def align
        find_anchors
        compute_boundaries
        @boundaries
      end

      private

      # Find matching sections between template and destination
      def find_anchors
        @anchors = []

        # Special case: if files are identical, create one anchor for entire file
        if @template_analysis.lines == @dest_analysis.lines
          @anchors << Anchor.new(
            1,
            @template_analysis.lines.length,
            1,
            @dest_analysis.lines.length,
            :exact_match,
            @template_analysis.lines.length
          )
          return
        end

        # Strategy: Find exact line matches and structural matches
        # 1. Exact line matches (including comments)
        # 2. Structural node matches (same signature)
        # 3. Freeze blocks (always anchors)

        # Build mapping of normalized lines for quick lookup
        template_line_map = build_line_map(@template_analysis)
        dest_line_map = build_line_map(@dest_analysis)

        # Find exact line matches using longest common subsequence approach
        exact_matches = find_exact_line_matches(template_line_map, dest_line_map)

        # Convert matches to anchors, merging consecutive matches
        @anchors = merge_consecutive_matches(exact_matches)

        # Add freeze block anchors
        add_freeze_block_anchors

        # Sort anchors by position
        @anchors.sort_by! { |a| [a.template_start, a.dest_start] }
      end

      def build_line_map(analysis)
        map = {}
        # Keywords that are too generic to use as anchors on their own
        generic_keywords = %w[end else elsif when rescue ensure]
        
        # Get line numbers covered by statement nodes - these shouldn't be matched line-by-line
        statement_lines = Set.new
        analysis.statements.each do |stmt|
          (stmt.location.start_line..stmt.location.end_line).each do |line_num|
            statement_lines << line_num
          end
        end
        
        analysis.lines.each_with_index do |line, idx|
          line_num = idx + 1
          normalized = line.strip
          next if normalized.empty?
          # Skip overly generic lines that appear in many contexts
          next if generic_keywords.include?(normalized)
          # Skip lines that are part of statement nodes - they should be matched by signature
          next if statement_lines.include?(line_num)
          map[line_num] = normalized
        end
        map
      end

      def find_exact_line_matches(template_map, dest_map)
        matches = []

        # Build reverse mapping from normalized content to line numbers
        dest_content_to_lines = {}
        dest_map.each do |line_num, content|
          dest_content_to_lines[content] ||= []
          dest_content_to_lines[content] << line_num
        end

        # Find matches - for each template line, find first matching dest line
        used_dest_lines = Set.new

        template_map.keys.sort.each do |t_line|
          content = template_map[t_line]
          next unless dest_content_to_lines[content]

          # Find first unused destination line with matching content
          d_line = dest_content_to_lines[content].find { |dl| !used_dest_lines.include?(dl) }
          next unless d_line

          matches << {
            template_line: t_line,
            dest_line: d_line,
            content: content,
          }

          used_dest_lines << d_line
        end

        matches
      end

      def merge_consecutive_matches(matches)
        return [] if matches.empty?

        anchors = []
        current_start_t = matches[0][:template_line]
        current_start_d = matches[0][:dest_line]
        current_end_t = current_start_t
        current_end_d = current_start_d

        matches[1..-1].each do |match|
          t_line = match[:template_line]
          d_line = match[:dest_line]

          # Check if this extends the current sequence
          if t_line == current_end_t + 1 && d_line == current_end_d + 1
            current_end_t = t_line
            current_end_d = d_line
          else
            # Save current anchor if it's substantial (at least 1 line)
            if current_end_t - current_start_t >= 0
              anchors << Anchor.new(
                current_start_t,
                current_end_t,
                current_start_d,
                current_end_d,
                :exact_match,
                current_end_t - current_start_t + 1
              )
            end

            # Start new sequence
            current_start_t = t_line
            current_start_d = d_line
            current_end_t = t_line
            current_end_d = d_line
          end
        end

        # Don't forget the last anchor
        if current_end_t - current_start_t >= 0
          anchors << Anchor.new(
            current_start_t,
            current_end_t,
            current_start_d,
            current_end_d,
            :exact_match,
            current_end_t - current_start_t + 1
          )
        end

        anchors
      end

      def add_freeze_block_anchors
        # Freeze blocks in destination should always be preserved as anchors
        @dest_analysis.freeze_blocks.each do |block|
          line_range = block[:line_range]

          # Check if there's a corresponding freeze block in template
          template_block = @template_analysis.freeze_blocks.find do |tb|
            tb[:start_marker] == block[:start_marker]
          end

          if template_block
            # Check if there's already an anchor covering this range
            # (from exact line matches)
            existing_anchor = @anchors.find do |a|
              a.template_start <= template_block[:line_range].begin &&
                a.template_end >= template_block[:line_range].end &&
                a.dest_start <= line_range.begin &&
                a.dest_end >= line_range.end
            end

            # Only create freeze block anchor if not already covered
            unless existing_anchor
              # Both files have this freeze block - create anchor
              @anchors << Anchor.new(
                template_block[:line_range].begin,
                template_block[:line_range].end,
                line_range.begin,
                line_range.end,
                :freeze_block,
                100 # High score for freeze blocks
              )
            end
          end
        end
      end

      def compute_boundaries
        @boundaries = []

        # Special case: no anchors means entire files are boundaries
        if @anchors.empty?
          @boundaries << Boundary.new(
            1..@template_analysis.lines.length,
            1..@dest_analysis.lines.length,
            nil,
            nil
          )
          return
        end

        # Boundary before first anchor
        first_anchor = @anchors.first
        if first_anchor.template_start > 1 || first_anchor.dest_start > 1
          template_range = first_anchor.template_start > 1 ? (1..first_anchor.template_start - 1) : nil
          dest_range = first_anchor.dest_start > 1 ? (1..first_anchor.dest_start - 1) : nil

          if template_range || dest_range
            @boundaries << Boundary.new(template_range, dest_range, nil, first_anchor)
          end
        end

        # Boundaries between consecutive anchors
        @anchors.each_cons(2) do |prev_anchor, next_anchor|
          template_gap_start = prev_anchor.template_end + 1
          template_gap_end = next_anchor.template_start - 1
          dest_gap_start = prev_anchor.dest_end + 1
          dest_gap_end = next_anchor.dest_start - 1

          template_range = template_gap_end >= template_gap_start ? (template_gap_start..template_gap_end) : nil
          dest_range = dest_gap_end >= dest_gap_start ? (dest_gap_start..dest_gap_end) : nil

          if template_range || dest_range
            @boundaries << Boundary.new(template_range, dest_range, prev_anchor, next_anchor)
          end
        end

        # Boundary after last anchor
        last_anchor = @anchors.last
        template_remaining = last_anchor.template_end < @template_analysis.lines.length
        dest_remaining = last_anchor.dest_end < @dest_analysis.lines.length

        if template_remaining || dest_remaining
          template_range = template_remaining ? (last_anchor.template_end + 1..@template_analysis.lines.length) : nil
          dest_range = dest_remaining ? (last_anchor.dest_end + 1..@dest_analysis.lines.length) : nil

          if template_range || dest_range
            @boundaries << Boundary.new(template_range, dest_range, last_anchor, nil)
          end
        end
      end
    end
  end
end
