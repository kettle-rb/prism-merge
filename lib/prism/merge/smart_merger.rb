# frozen_string_literal: true

module Prism
  module Merge
    # Orchestrates the smart merge process using FileAnalysis, FileAligner,
    # ConflictResolver, and MergeResult to merge two Ruby files intelligently.
    #
    # SmartMerger provides flexible configuration for different merge scenarios:
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Version file merge (template updates win)
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_match_preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #   # Result: VERSION = "2.0.0" (from template), new constants added
    #
    # @example Appraisals merge (destination customizations preserved)
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_match_preference: :destination,  # default
    #     add_template_only_nodes: false             # default
    #   )
    #   result = merger.merge
    #   # Result: Custom gem versions preserved, template-only blocks skipped
    #
    # @example Custom signature matching
    #   sig_gen = ->(node) { [node.class.name, node.name] }
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_generator: sig_gen
    #   )
    #
    # @see FileAnalysis
    # @see FileAligner
    # @see ConflictResolver
    # @see MergeResult
    class SmartMerger
      # @return [FileAnalysis] Analysis of the template file
      attr_reader :template_analysis
      
      # @return [FileAnalysis] Analysis of the destination file
      attr_reader :dest_analysis
      
      # @return [FileAligner] Aligner for finding matches and differences
      attr_reader :aligner
      
      # @return [ConflictResolver] Resolver for handling conflicting content
      attr_reader :resolver
      
      # @return [MergeResult] Result object tracking merged content
      attr_reader :result

      # Creates a new SmartMerger for intelligent Ruby file merging.
      #
      # @param template_content [String] Template Ruby source code
      # @param dest_content [String] Destination Ruby source code
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom node signatures.
      #   The proc receives a Prism node and should return an array representing its signature.
      #   Nodes with identical signatures are considered matches during merge.
      #   Default: Uses {FileAnalysis#default_signature} which matches:
      #   - Conditionals by condition only (not body)
      #   - Assignments by name only (not value)
      #   - Method calls by name and args (not block)
      #
      # @param signature_match_preference [Symbol] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations).
      #     Use for Appraisals files, configs with project-specific values.
      #   - `:template` - Use template version (applies updates).
      #     Use for version files, canonical configs, conditional implementations.
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes.
      #     Use for templates with placeholder/example content.
      #   - `true` - Add template-only nodes to result.
      #     Use when template has new required constants/methods to add.
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      #
      # @example Basic usage
      #   merger = SmartMerger.new(template, destination)
      #   result = merger.merge
      #
      # @example Template updates win (version files)
      #   merger = SmartMerger.new(
      #     template,
      #     destination,
      #     signature_match_preference: :template,
      #     add_template_only_nodes: true
      #   )
      #
      # @example Destination customizations win (Appraisals)
      #   merger = SmartMerger.new(
      #     template,
      #     destination,
      #     signature_match_preference: :destination,
      #     add_template_only_nodes: false
      #   )
      #
      # @example Custom signature matching
      #   sig_gen = lambda do |node|
      #     case node
      #     when Prism::DefNode
      #       [:method, node.name]
      #     else
      #       [node.class.name, node.slice]
      #     end
      #   end
      #
      #   merger = SmartMerger.new(
      #     template,
      #     destination,
      #     signature_generator: sig_gen
      #   )
      def initialize(template_content, dest_content, signature_generator: nil, signature_match_preference: :destination, add_template_only_nodes: false)
        @template_content = template_content
        @dest_content = dest_content
        @signature_match_preference = signature_match_preference
        @add_template_only_nodes = add_template_only_nodes
        @template_analysis = FileAnalysis.new(template_content, signature_generator: signature_generator)
        @dest_analysis = FileAnalysis.new(dest_content, signature_generator: signature_generator)
        @aligner = FileAligner.new(@template_analysis, @dest_analysis)
        @resolver = ConflictResolver.new(@template_analysis, @dest_analysis, 
          signature_match_preference: signature_match_preference,
          add_template_only_nodes: add_template_only_nodes)
        @result = MergeResult.new
      end

      # Performs the intelligent merge of template and destination files.
      #
      # The merge process:
      # 1. Validates both files for syntax errors
      # 2. Finds anchors (matching sections) and boundaries (differences)
      # 3. Processes anchors and boundaries in order
      # 4. Returns merged content as a string
      #
      # Merge behavior is controlled by constructor parameters:
      # - `signature_match_preference`: Which version wins for matching nodes
      # - `add_template_only_nodes`: Whether to add template-only content
      #
      # @return [String] The merged Ruby source code
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      #
      # @example Basic merge
      #   merger = SmartMerger.new(template, destination)
      #   result = merger.merge
      #   File.write("output.rb", result)
      #
      # @example With error handling
      #   begin
      #     result = merger.merge
      #   rescue Prism::Merge::TemplateParseError => e
      #     puts "Template error: #{e.message}"
      #     puts "Parse errors: #{e.parse_result.errors}"
      #   end
      #
      # @see #merge_with_debug for detailed merge information
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

      # Performs merge and returns detailed debug information.
      #
      # This method provides comprehensive information about merge decisions,
      # useful for debugging, testing, and understanding merge behavior.
      #
      # @return [Hash] Hash containing:
      #   - `:content` [String] - Final merged content
      #   - `:debug` [String] - Line-by-line provenance information
      #   - `:statistics` [Hash] - Counts of merge decisions:
      #     - `:kept_template` - Lines from template (no conflict)
      #     - `:kept_destination` - Lines from destination (no conflict)
      #     - `:replaced` - Template replaced matching destination
      #     - `:appended` - Destination-only content added
      #     - `:freeze_block` - Lines from freeze blocks
      #
      # @example Get merge statistics
      #   result = merger.merge_with_debug
      #   puts "Template lines: #{result[:statistics][:kept_template]}"
      #   puts "Replaced lines: #{result[:statistics][:replaced]}"
      #
      # @example Debug line provenance
      #   result = merger.merge_with_debug
      #   puts result[:debug]
      #   # Output shows source file and decision for each line:
      #   # Line 1: [KEPT_TEMPLATE] # frozen_string_literal: true
      #   # Line 2: [KEPT_TEMPLATE]
      #   # Line 3: [REPLACED] VERSION = "2.0.0"
      #
      # @see #merge for basic merge without debug info
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
        # For signature matches, use the configured preference
        if @signature_match_preference == :template
          # Use template version (for updates/canonical values)
          anchor.template_range.each do |line_num|
            line = @template_analysis.line_at(line_num)
            @result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_REPLACED,
              template_line: line_num,
            )
          end
        else
          # Use destination version (for customizations)
          anchor.dest_range.each do |line_num|
            line = @dest_analysis.line_at(line_num)
            @result.add_line(
              line.chomp,
              decision: MergeResult::DECISION_REPLACED,
              dest_line: line_num,
            )
          end
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
