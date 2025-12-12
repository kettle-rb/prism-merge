# frozen_string_literal: true

module Prism
  module Merge
    # A merger that uses section-based semantics with recursive body merging for cleaner merging.
    #
    # SmartMerger:
    # 1. Converts each top-level node into a "section" identified by its signature
    # 2. Uses SectionTyping-style merge logic to decide which sections to include
    # 3. Recursively merges matching class/module/block bodies
    # 4. Outputs each selected node exactly once (with its comments)
    #
    # This approach avoids the complexity of tracking line ranges for anchors
    # and boundaries, which can lead to duplicate content when comments are
    # attached to multiple overlapping ranges.
    #
    # ## Merge Algorithm
    #
    # 1. Parse both template and destination files
    # 2. Generate signatures for all top-level nodes in both files
    # 3. Build a signature -> node map for destination
    # 4. Walk template nodes in order:
    #    - If signature matches a dest node:
    #      - If class/module/block with mergeable body: recursively merge bodies
    #      - Otherwise: output based on preference
    #    - If template-only: output if add_template_only_nodes is true
    # 5. Output any remaining dest-only nodes
    #
    # ## Recursive Body Merging
    #
    # When matching class/module definitions or CallNodes with blocks are found,
    # the merger recursively merges their body contents. This allows template
    # updates to nested methods/constants to be merged with destination customizations.
    #
    # @example Basic merge
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Template wins with additions
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      # @return [Hash{Symbol,String => #call}, nil] Node typing configuration
      attr_reader :node_typing

      # @return [Integer, Float] Maximum recursion depth for body merging
      attr_reader :max_recursion_depth

      # @return [Hash, nil] Options to pass to Text::SmartMerger for comment-only files
      attr_reader :text_merger_options

      # Creates a new SmartMerger.
      #
      # @param template_content [String] Template Ruby source code
      # @param dest_content [String] Destination Ruby source code
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :template, :destination, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add template-only nodes
      # @param freeze_token [String, nil] Token for freeze block markers
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param max_recursion_depth [Integer, Float] Maximum depth for recursive body merging.
      #   Default: Float::INFINITY (no limit). This is a safety valve that users can set
      #   if they encounter edge cases.
      # @param current_depth [Integer] Current recursion depth (internal use)
      # @param match_refiner [#call, nil] Optional match refiner (unused but accepted for API compatibility)
      # @param regions [Array<Hash>, nil] Region configurations (unused but accepted for API compatibility)
      # @param region_placeholder [String, nil] Custom placeholder prefix (unused but accepted for API compatibility)
      # @param text_merger_options [Hash, nil] Options to pass to Text::SmartMerger when
      #   merging comment-only files (files with no Ruby code statements). Supported options:
      #   - :freeze_token - Token for freeze block markers (defaults to @freeze_token or "text-merge")
      #   - Any other options supported by Ast::Merge::Text::SmartMerger
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        freeze_token: nil,
        node_typing: nil,
        max_recursion_depth: Float::INFINITY,
        current_depth: 0,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        text_merger_options: nil
      )
        @node_typing = node_typing
        @max_recursion_depth = max_recursion_depth
        @current_depth = current_depth
        @text_merger_options = text_merger_options

        # Wrap signature_generator to include node_typing processing
        effective_signature_generator = build_effective_signature_generator(signature_generator, node_typing)

        super(
          template_content,
          dest_content,
          signature_generator: effective_signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder
        )
      end

      # Perform the merge and return a hash with content, debug info, and statistics.
      #
      # @return [Hash] Hash with :content, :debug, and :statistics keys
      def merge_with_debug
        result = merge
        {
          content: result.to_s,
          debug: {
            template_statements: @template_analysis&.statements&.size || 0,
            dest_statements: @dest_analysis&.statements&.size || 0,
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            freeze_token: @freeze_token,
          },
          statistics: result.respond_to?(:statistics) ? result.statistics : {},
        }
      end

      protected

      # @return [Class] The analysis class for Ruby files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token for Ruby
      def default_freeze_token
        "prism-merge"
      end

      # @return [Class] The result class for Ruby files
      def result_class
        MergeResult
      end

      # @return [Class, nil] No aligner needed for SmartMerger
      def aligner_class
        nil
      end

      # @return [Class, nil] No resolver needed for SmartMerger
      def resolver_class
        nil
      end

      # Build the result (no-arg constructor for Prism)
      def build_result
        MergeResult.new
      end

      # @return [Class] The template parse error class for Ruby
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for Ruby
      def destination_parse_error_class
        DestinationParseError
      end

      # Perform the SmartMerger's section-based merge with recursive body merging.
      #
      # @return [MergeResult] The merge result
      def perform_merge
        validate_files!

        # Handle special case: files with no statements (comment-only files)
        # This happens with files that only contain comments like `# frozen_string_literal: true`
        if @template_analysis.statements.empty? && @dest_analysis.statements.empty?
          return merge_comment_only_files
        end

        # Build signature maps for quick lookup
        template_by_signature = build_signature_map(@template_analysis)
        build_signature_map(@dest_analysis)

        # Track which signatures we've output (to avoid duplicates)
        output_signatures = Set.new

        # Track which dest line ranges have been output (to avoid duplicating nested content)
        output_dest_line_ranges = []

        # Process destination nodes in their original order to preserve dest-only node positions
        # This ensures dest-only nodes appear in their natural position relative to matched nodes
        @dest_analysis.statements.each do |dest_node|
          dest_signature = @dest_analysis.generate_signature(dest_node)

          # Skip if already output (shouldn't happen but safety check)
          next if dest_signature && output_signatures.include?(dest_signature)

          # Skip if this dest node is inside a dest range we've already output
          # (e.g., a nested node inside a Gem::Specification block)
          node_range = dest_node.location.start_line..dest_node.location.end_line
          next if output_dest_line_ranges.any? { |range| range.cover?(node_range.begin) && range.cover?(node_range.end) }

          if dest_signature && template_by_signature.key?(dest_signature)
            # Matched node - merge with template version
            template_node = template_by_signature[dest_signature]
            output_signatures << dest_signature

            if should_merge_recursively?(template_node, dest_node)
              # Recursively merge class/module/block bodies
              merge_node_body_recursively(template_node, dest_node)
            else
              # Output based on preference
              node_preference = preference_for_node(template_node, dest_node)

              if node_preference == :template
                add_node_to_result(@result, template_node, @template_analysis, :template)
              else
                add_node_to_result(@result, dest_node, @dest_analysis, :destination)
              end
            end

            output_dest_line_ranges << node_range
          else
            # Dest-only node - output it in place
            add_node_to_result(@result, dest_node, @dest_analysis, :destination)
            output_dest_line_ranges << node_range
            output_signatures << dest_signature if dest_signature
          end
        end

        # Add template-only nodes if configured
        if @add_template_only_nodes
          @template_analysis.statements.each do |template_node|
            signature = @template_analysis.generate_signature(template_node)

            # Skip if already output (matched with dest)
            next if signature && output_signatures.include?(signature)

            add_node_to_result(@result, template_node, @template_analysis, :template)
            output_signatures << signature if signature
          end
        end

        @result
      end

      private

      # Check if a node has a freeze marker in its leading comments OR
      # contains a freeze marker anywhere in its content.
      #
      # Nodes with freeze markers always prefer destination version during merge.
      # This ensures that:
      # 1. Top-level nodes with freeze markers as leading comments are preserved
      # 2. Nodes containing freeze markers in their body (e.g., inside blocks) are preserved
      # 3. Already-wrapped FrozenWrapper nodes are recognized as frozen
      #
      # @param node [Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper] The node to check
      # @return [Boolean] true if the node has or contains a freeze marker
      def frozen_node?(node)
        # Already wrapped as frozen (includes Freezable module)
        return true if node.is_a?(Ast::Merge::Freezable)

        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # Check for freeze marker in leading comments
        if actual_node.respond_to?(:location) && actual_node.location.respond_to?(:leading_comments)
          return true if actual_node.location.leading_comments.any? { |c| c.slice.match?(freeze_pattern) }
        end

        # Check if node content contains a freeze marker (for nested freeze blocks)
        if actual_node.respond_to?(:slice)
          return true if actual_node.slice.match?(freeze_pattern)
        end

        false
      end

      # Check if a node contains freeze blocks within its body/content.
      #
      # This is used to detect if a class, module, block, or other container
      # has freeze markers anywhere inside it (not just as a leading comment).
      #
      # @param node [Prism::Node] The node to check
      # @param analysis [FileAnalysis] The file analysis (for context)
      # @return [Boolean] true if the node contains freeze markers
      def node_contains_freeze_blocks?(node, analysis = nil)
        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # Check if node content contains a freeze marker
        if actual_node.respond_to?(:slice)
          return true if actual_node.slice.match?(freeze_pattern)
        end

        false
      end

      def validate_files!
        unless @template_analysis.valid?
          raise TemplateParseError.new(
            "Template file has parsing errors",
            content: @template_content,
            parse_result: @template_analysis.parse_result,
          )
        end

        unless @dest_analysis.valid?
          raise DestinationParseError.new(
            "Destination file has parsing errors",
            content: @dest_content,
            parse_result: @dest_analysis.parse_result,
          )
        end
      end

      # Handle merging of files that contain only comments (no code statements).
      #
      # For comment-only files (like files with just `# frozen_string_literal: true`),
      # there are no AST nodes to match. We delegate to Ast::Merge::Text::SmartMerger
      # which provides intelligent line-based merging with freeze block support.
      #
      # @return [MergeResult] The merge result
      def merge_comment_only_files
        # Build options for text merger, merging defaults with any custom options
        text_options = {
          preference: default_preference,
          add_template_only_nodes: @add_template_only_nodes,
          freeze_token: @freeze_token || ::Ast::Merge::Text::SmartMerger::DEFAULT_FREEZE_TOKEN,
        }
        text_options.merge!(@text_merger_options) if @text_merger_options

        # Delegate to text merger for intelligent line-based merging
        text_merger = ::Ast::Merge::Text::SmartMerger.new(
          @template_content,
          @dest_content,
          **text_options,
        )

        text_result = text_merger.merge

        # Convert text merge result to our result format
        text_result.to_s.each_line.with_index do |line, idx|
          @result.add_line(
            line.chomp,
            decision: MergeResult::DECISION_KEPT_DEST, # Text merger handles decisions internally
            dest_line: idx + 1,
          )
        end

        @result
      end

      # Build a map of signature -> node for an analysis.
      #
      # @param analysis [FileAnalysis] The file analysis
      # @return [Hash{Array => Prism::Node}] Map of signatures to nodes
      def build_signature_map(analysis)
        map = {}
        analysis.statements.each do |node|
          sig = analysis.generate_signature(node)
          # Only map nodes with signatures, and keep first occurrence
          map[sig] ||= node if sig
        end
        map
      end

      # Determine preference for a specific node pair.
      #
      # Frozen nodes (those with freeze markers in leading_comments) always
      # prefer the destination version, as they represent user customizations
      # that should be preserved across template updates.
      #
      # @param template_node [Prism::Node] Template node
      # @param dest_node [Prism::Node] Destination node
      # @return [Symbol] :template or :destination
      def preference_for_node(template_node, dest_node)
        # Frozen nodes always prefer destination - they're user customizations
        return :destination if frozen_node?(dest_node)

        return @preference unless @preference.is_a?(Hash)

        # Process nodes through node_typing if configured
        typed_template = @node_typing ? ::Ast::Merge::NodeTyping.process(template_node, @node_typing) : template_node
        typed_dest = @node_typing ? ::Ast::Merge::NodeTyping.process(dest_node, @node_typing) : dest_node

        # Check for merge_type from NodeTyping
        if ::Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        if ::Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        default_preference
      end

      def default_preference
        if @preference.is_a?(Hash)
          @preference.fetch(:default, :destination)
        else
          @preference
        end
      end

      # Build an effective signature generator that incorporates node_typing.
      #
      # When node_typing is provided, this wraps the signature_generator (or creates one)
      # to process nodes through node_typing first. This allows:
      #
      # - Custom signature_generators to receive typed nodes with merge_type
      # - Default signature generation to work with the underlying node (via unwrap in
      #   FileAnalyzable#generate_signature)
      #
      # The node_typing processing happens here (for signature generation) AND in
      # preference_for_node (for preference determination), so typed nodes are handled
      # consistently in both contexts.
      #
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param node_typing [Hash, nil] Node typing configuration
      # @return [Proc, nil] Combined signature generator, or nil if neither is provided
      def build_effective_signature_generator(signature_generator, node_typing)
        return signature_generator unless node_typing

        ->(node) {
          # First, process through node_typing to potentially add merge_type
          processed_node = ::Ast::Merge::NodeTyping.process(node, node_typing)

          # Then, pass to signature_generator or return processed node for default handling
          # FileAnalyzable#generate_signature will unwrap Wrappers for default signature computation
          if signature_generator
            signature_generator.call(processed_node)
          else
            processed_node
          end
        }
      end

      # Add a node to the result, including its leading and trailing comments.
      #
      # @param result [MergeResult] The merge result
      # @param node [Prism::Node] The node to add
      # @param analysis [FileAnalysis] The source analysis
      # @param source [Symbol] :template or :destination
      def add_node_to_result(result, node, analysis, source)
        decision = case source
        when :template
          MergeResult::DECISION_KEPT_TEMPLATE
        else
          MergeResult::DECISION_KEPT_DEST
        end

        # Get leading comments attached to the node
        leading_comments = node.location.respond_to?(:leading_comments) ? node.location.leading_comments : []

        # Add leading comments first (includes freeze markers if present)
        # Also add any blank lines between consecutive comments
        prev_comment_line = nil
        leading_comments.each do |comment|
          line_num = comment.location.start_line

          # Add blank lines between this comment and the previous one
          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              line = analysis.line_at(blank_line_num)&.chomp || ""
              if source == :template
                result.add_line(line, decision: decision, template_line: blank_line_num)
              else
                result.add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end

          prev_comment_line = line_num
        end

        # Add blank line before node if there's a gap after comments
        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          if node.location.start_line > last_comment_line + 1
            # There's a gap - add blank lines
            ((last_comment_line + 1)...node.location.start_line).each do |line_num|
              line = analysis.line_at(line_num)&.chomp || ""
              if source == :template
                result.add_line(line, decision: decision, template_line: line_num)
              else
                result.add_line(line, decision: decision, dest_line: line_num)
              end
            end
          end
        end

        # Add node source lines
        (node.location.start_line..node.location.end_line).each do |line_num|
          line = analysis.line_at(line_num)&.chomp || ""

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end
        end

        # Add trailing blank line if needed for separation
        trailing_line = node.location.end_line + 1
        trailing_content = analysis.line_at(trailing_line)
        if trailing_content && trailing_content.strip.empty?
          if source == :template
            result.add_line("", decision: decision, template_line: trailing_line)
          else
            result.add_line("", decision: decision, dest_line: trailing_line)
          end
        end

        # Add trailing comments attached to the node (e.g., end-of-file comments)
        trailing_comments = node.location.respond_to?(:trailing_comments) ? node.location.trailing_comments : []
        trailing_comments.each do |comment|
          line_num = comment.location.start_line
          line = analysis.line_at(line_num)&.chomp || comment.slice.rstrip

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end
        end
      end

      # Determines if two matching nodes should be recursively merged.
      #
      # Recursive merge is performed for matching class/module definitions and
      # CallNodes with blocks to intelligently combine their body contents
      # (nested methods, constants, etc.). This allows template updates to
      # internals to be merged with destination customizations.
      #
      # @param template_node [Prism::Node, nil] Node from template file
      # @param dest_node [Prism::Node, nil] Node from destination file
      # @return [Boolean] true if nodes should be recursively merged
      #
      # @note Recursive merge is NOT performed for:
      #   - Conditional nodes (if/unless) - treated as atomic units
      #   - Nodes of different types
      #   - Blocks whose body contains only literals/expressions with no mergeable statements
      #   - When max_recursion_depth has been reached (safety valve)
      def should_merge_recursively?(template_node, dest_node)
        return false unless template_node && dest_node

        # Safety valve: stop recursion if max depth reached
        return false if @current_depth >= @max_recursion_depth

        # Unwrap FrozenWrapper nodes to check the actual node type
        actual_template = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
        actual_dest = dest_node.respond_to?(:unwrap) ? dest_node.unwrap : dest_node

        # Both nodes must be the same type
        return false unless actual_template.class == actual_dest.class

        # Determine if this node type supports recursive merging
        case actual_template
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          # Class/module definitions - merge their body contents
          true
        when Prism::CallNode
          # Only merge if both have blocks with mergeable content
          return false unless actual_template.block && actual_dest.block

          body_has_mergeable_statements?(actual_template.block.body) &&
            body_has_mergeable_statements?(actual_dest.block.body)
        when Prism::BeginNode
          # begin/rescue/ensure blocks - merge statements if both have them
          !!(actual_template.statements && actual_dest.statements)
        else
          false
        end
      end

      # Check if a body (StatementsNode) contains statements that could be merged.
      #
      # Mergeable statements are those that can generate signatures and be
      # independently matched between template and destination. This includes
      # method definitions, class/module definitions, method calls, assignments, etc.
      #
      # Bodies containing only literals (strings, numbers, arrays, hashes) or
      # simple expressions should not be recursively merged as there's nothing
      # to align - they should be treated atomically.
      #
      # @param body [Prism::StatementsNode, nil] The body to check
      # @return [Boolean] true if the body contains mergeable statements
      # @api private
      def body_has_mergeable_statements?(body)
        return false unless body.is_a?(Prism::StatementsNode)
        return false if body.body.empty?

        body.body.any? { |stmt| mergeable_statement?(stmt) }
      end

      # Check if a statement is mergeable (can generate a signature).
      #
      # @param node [Prism::Node] The node to check
      # @return [Boolean] true if this node type can be merged
      # @api private
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

      # Recursively merges the body of matching class, module, or call-with-block nodes.
      #
      # This method extracts the body content (everything between the opening
      # declaration and the closing 'end'), creates a new nested SmartMerger to merge
      # those bodies, and then reassembles the complete node with the merged body.
      #
      # @param template_node [Prism::Node] Node from template
      # @param dest_node [Prism::Node] Node from destination
      #
      # @note The nested merger is configured with:
      #   - Same signature_generator, preference, add_template_only_nodes, and freeze_token
      #   - Incremented current_depth to track recursion level
      #
      # @api private
      def merge_node_body_recursively(template_node, dest_node)
        # Unwrap FrozenWrapper nodes to get actual nodes
        actual_template = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
        actual_dest = dest_node.respond_to?(:unwrap) ? dest_node.unwrap : dest_node

        # Extract the body source for both nodes
        template_body = extract_node_body(actual_template, @template_analysis)
        dest_body = extract_node_body(actual_dest, @dest_analysis)

        # Recursively merge the bodies with incremented depth
        body_merger = SmartMerger.new(
          template_body,
          dest_body,
          signature_generator: @template_analysis.instance_variable_get(:@signature_generator),
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          freeze_token: @freeze_token,
          max_recursion_depth: @max_recursion_depth,
          current_depth: @current_depth + 1,
          node_typing: @node_typing,
        )
        merged_body = body_merger.merge.rstrip

        # Get preference for this specific node pair
        node_preference = preference_for_node(template_node, dest_node)

        # Determine which comments to use:
        # - If template preference and template has comments, use template's
        # - If template preference but template has NO comments, preserve dest's comments
        # - If dest preference, use dest's comments
        template_comments = actual_template.location.respond_to?(:leading_comments) ? actual_template.location.leading_comments : []
        dest_comments = actual_dest.location.respond_to?(:leading_comments) ? actual_dest.location.leading_comments : []

        # Choose comment source: prefer dest comments if template has none (to preserve existing headers)
        if node_preference == :template && template_comments.empty? && dest_comments.any?
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = @dest_analysis
        elsif node_preference == :template
          comment_source = :template
          leading_comments = template_comments
          comment_analysis = @template_analysis
        else
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = @dest_analysis
        end

        # Source for the opening/closing lines follows node_preference
        source_analysis = (node_preference == :template) ? @template_analysis : @dest_analysis
        source_node = (node_preference == :template) ? actual_template : actual_dest
        decision = MergeResult::DECISION_REPLACED

        # Add leading comments with blank lines between them preserved
        prev_comment_line = nil
        leading_comments.each do |comment|
          line_num = comment.location.start_line

          # Add blank lines between this comment and the previous one
          if prev_comment_line && line_num > prev_comment_line + 1
            ((prev_comment_line + 1)...line_num).each do |blank_line_num|
              line = comment_analysis.line_at(blank_line_num)&.chomp || ""
              if comment_source == :template
                @result.add_line(line, decision: decision, template_line: blank_line_num)
              else
                @result.add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          line = comment_analysis.line_at(line_num)&.chomp || comment.slice.rstrip
          if comment_source == :template
            @result.add_line(line, decision: decision, template_line: line_num)
          else
            @result.add_line(line, decision: decision, dest_line: line_num)
          end

          prev_comment_line = line_num
        end

        # Add blank lines between comments and node if needed
        # Note: blank lines come from comment_analysis to match the comment source
        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          # Calculate the gap based on source_node's start line
          if source_node.location.start_line > last_comment_line + 1
            ((last_comment_line + 1)...source_node.location.start_line).each do |line_num|
              line = comment_analysis.line_at(line_num)&.chomp || ""
              if comment_source == :template
                @result.add_line(line, decision: decision, template_line: line_num)
              else
                @result.add_line(line, decision: decision, dest_line: line_num)
              end
            end
          end
        end

        # Add the opening line (based on preference)
        opening_line = source_analysis.line_at(source_node.location.start_line)
        @result.add_line(
          opening_line.chomp,
          decision: decision,
          template_line: (node_preference == :template) ? source_node.location.start_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.start_line : nil,
        )

        # Add the merged body
        merged_body.lines.each do |line|
          @result.add_line(
            line.chomp,
            decision: decision,
            template_line: nil,
            dest_line: nil,
          )
        end

        # Add the closing 'end'
        end_line = source_analysis.line_at(source_node.location.end_line)
        @result.add_line(
          end_line.chomp,
          decision: decision,
          template_line: (node_preference == :template) ? source_node.location.end_line : nil,
          dest_line: (node_preference == :destination) ? source_node.location.end_line : nil,
        )
      end

      # Extracts the body content of a node (without declaration and closing 'end').
      #
      # @param node [Prism::Node] The node to extract body from
      # @param analysis [FileAnalysis] The file analysis containing the node
      # @return [String] The extracted body content
      #
      # @api private
      def extract_node_body(node, analysis)
        # Get the statements node based on node type
        statements_node = case node
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::LambdaNode
          node.body
        when Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode
          node.statements
        when Prism::CallNode
          node.block&.body
        when Prism::BeginNode
          node.statements
        when Prism::ParenthesesNode
          node.body
        else
          if node.respond_to?(:body)
            node.body
          elsif node.respond_to?(:statements)
            node.statements
          elsif node.respond_to?(:block) && node.block
            node.block.body
          end
        end

        return "" unless statements_node&.is_a?(Prism::StatementsNode)

        body_statements = statements_node.body
        return "" if body_statements.empty?

        # Get the line range of the body
        body_start_line = case node
        when Prism::CallNode
          node.block.opening_loc ? node.block.opening_loc.start_line + 1 : body_statements.first.location.start_line
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          node.location.start_line + 1
        else
          body_statements.first.location.start_line
        end

        body_end_line = case node
        when Prism::CallNode
          node.block.closing_loc ? node.block.closing_loc.start_line - 1 : body_statements.last.location.end_line
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          node.end_keyword_loc ? node.end_keyword_loc.start_line - 1 : body_statements.last.location.end_line
        else
          body_statements.last.location.end_line
        end

        # Extract the source lines for the body
        lines = []
        (body_start_line..body_end_line).each do |line_num|
          lines << analysis.line_at(line_num).chomp
        end
        lines.join("\n") + "\n"
      end
    end
  end
end
