# frozen_string_literal: true

module Prism
  module Merge
    # Orchestrates the top-level merge of two Ruby files parsed by Prism.
    #
    # Uses a **three-phase matching** strategy to pair template nodes with
    # destination nodes before emitting the merged result:
    #
    # 1. **Phase 1 — Exact signature match.**
    #    Pairs nodes whose structural signatures (method name + params,
    #    call name + args, etc.) are identical. This is the fastest phase
    #    and handles the vast majority of nodes.
    #
    # 2. **Phase 2 — Similarity match at the same depth.**
    #    For nodes left unmatched after Phase 1, computes body-text Jaccard
    #    similarity ({Ast::Merge::JaccardSimilarity}) to pair probable
    #    renames or minor refactors. Only operates on the residual
    #    unmatched sets, keeping cost proportional to orphan count.
    #
    # 3. **Phase 3 — Cross-depth match.**
    #    For nodes still unmatched after Phase 2, searches recursively into
    #    destination subtrees (conditionals, begin/rescue, call blocks) to
    #    detect "moved" nodes — e.g. a template top-level +eval_gemfile+
    #    that the destination wrapped inside an +if+ block. Only runs on
    #    the tiny residual set surviving both previous phases.
    #
    # The phase ordering is critical: exact matches are locked in first so
    # that fuzzy Phase 2 scoring cannot accidentally consume a node that
    # belongs to a later exact match at a different position.
    #
    # @example Basic usage (internal — called by SmartMerger)
    #   runner = TopLevelMergeRunner.new(merger: smart_merger)
    #   result = runner.merge   # => MergeResult
    #
    # @see Ast::Merge::JaccardSimilarity   Jaccard token-set similarity
    # @see Ast::Merge::TrailingGroups::DestIterate  Template-only node positioning
    class TopLevelMergeRunner
      include ::Ast::Merge::TrailingGroups::DestIterate
      include ::Ast::Merge::JaccardSimilarity

      # Minimum Jaccard score for Phase 2 body-text matching.
      # Below this threshold, two nodes are too dissimilar to pair.
      #
      # @return [Float]
      SIMILARITY_THRESHOLD = 0.6

      # Minimum token count for meaningful Jaccard comparison.
      # Nodes with fewer body tokens than this are skipped in Phase 2
      # to avoid spurious matches on trivially short bodies.
      #
      # @return [Integer]
      MIN_BODY_TOKENS = 3

      # @return [SmartMerger] The merger instance driving this run
      attr_reader :merger

      # @param merger [SmartMerger] The merger to run
      def initialize(merger:)
        @merger = merger
      end

      # Execute the three-phase merge and return the result.
      #
      # @return [MergeResult] The merged output
      def merge
        return merger.send(:comment_only_file_merger).merge if comment_only_merge?

        template_by_signature = merger.send(:build_signature_map, merger.template_analysis)
        dest_by_signature = merger.send(:build_signature_map, merger.dest_analysis)
        prepare_comment_augmenters!(template_by_signature: template_by_signature, dest_by_signature: dest_by_signature)
        consumed_template_indices = Set.new
        sig_cursor = Hash.new(0)
        output_dest_line_ranges = []
        last_output_dest_line = merger.send(:emit_dest_prefix_lines, merger.result, merger.dest_analysis)

        # Phase 1: exact signature match (existing behavior).
        dest_sigs = ::Set.new(dest_by_signature.keys)

        # Phase 2: compute similarity-matched pairs from residual orphans.
        @similarity_pairs = compute_similarity_pairs(template_by_signature, dest_by_signature)

        # Phase 3: cross-depth search, but only for orphans surviving Phases 1+2.
        @deep_dest_sigs = compute_deep_sigs_for_orphans(
          template_by_signature, dest_sigs
        )

        trailing_groups, _matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: merger.template_analysis.statements,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { merger.template_analysis.generate_signature(node) },
          add_template_only_nodes: merger.add_template_only_nodes,
        )

        # Emit template-only nodes that precede the first matched template node
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
        end

        merger.dest_analysis.statements.each do |dest_node|
          last_output_dest_line = process_dest_node(
            dest_node: dest_node,
            template_by_signature: template_by_signature,
            consumed_template_indices: consumed_template_indices,
            sig_cursor: sig_cursor,
            output_dest_line_ranges: output_dest_line_ranges,
            last_output_dest_line: last_output_dest_line,
            trailing_groups: trailing_groups,
          )
        end

        # Safety net: emit any trailing groups whose anchor was never consumed
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices,
        ) do |info|
          merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
        end

        emit_dest_postlude_lines(last_output_dest_line)

        # Normalize consecutive blank lines left behind by comment dedup or node removal
        merger.result.normalize_consecutive_blank_lines!

        merger.result
      end

      private

      # Override the ast-merge hook to incorporate Phase 2 (similarity) and
      # Phase 3 (cross-depth) matches when deciding whether a template node
      # should be treated as "matched" vs "template-only".
      #
      # Called by {Ast::Merge::TrailingGroups::DestIterate} during trailing
      # group construction for each template node not matched by Phase 1.
      #
      # @param _node [Prism::Node] The template node under consideration
      # @param signature [Array, nil] The node's computed signature
      # @return [Boolean] true if the node should be treated as matched
      def trailing_group_node_matched?(_node, signature)
        return false unless signature

        # Phase 2: matched by body-text similarity?
        return true if @similarity_pairs&.key?(signature)

        # Phase 3: exists at a deeper depth in destination?
        return true if @deep_dest_sigs&.include?(signature)

        false
      end

      # ------------------------------------------------------------------
      # Phase 2: Body-text Jaccard similarity matching
      # ------------------------------------------------------------------

      # Compute similarity-based pairings for unmatched template nodes.
      #
      # After Phase 1 exact matching, some template and destination nodes
      # remain unpaired. This method extracts the body text of each
      # unmatched node, tokenizes it with {JaccardSimilarity#extract_tokens},
      # and uses greedy highest-score-first matching to pair probable
      # renames or minor refactors.
      #
      # Only nodes with meaningful body text (≥ {MIN_BODY_TOKENS} tokens)
      # are considered. The result is a Hash mapping template signature
      # to its similarity-paired destination signature.
      #
      # @param template_by_signature [Hash] Phase 1 template signature map
      # @param dest_by_signature [Hash] Phase 1 destination signature map
      # @return [Hash{Array => Array}] Template sig → dest sig pairs
      def compute_similarity_pairs(template_by_signature, dest_by_signature)
        pairs = {}
        template_sigs = ::Set.new(template_by_signature.keys)
        dest_sigs = ::Set.new(dest_by_signature.keys)
        matched_sigs = template_sigs & dest_sigs

        # Residual: unmatched signatures after Phase 1
        unmatched_t_sigs = template_sigs - matched_sigs
        unmatched_d_sigs = dest_sigs - matched_sigs

        return pairs if unmatched_t_sigs.empty? || unmatched_d_sigs.empty?

        # Build candidate lists: [{sig:, node:, tokens:}, ...]
        t_candidates = build_token_candidates(unmatched_t_sigs, template_by_signature, merger.template_analysis)
        d_candidates = build_token_candidates(unmatched_d_sigs, dest_by_signature, merger.dest_analysis)

        return pairs if t_candidates.empty? || d_candidates.empty?

        # Score all pairs, greedily assign best matches
        scored = []
        t_candidates.each do |tc|
          d_candidates.each do |dc|
            score = jaccard(tc[:tokens], dc[:tokens])
            scored << {t_sig: tc[:sig], d_sig: dc[:sig], score: score} if score > SIMILARITY_THRESHOLD
          end
        end

        scored.sort_by! { |s| -s[:score] }

        used_t = ::Set.new
        used_d = ::Set.new
        scored.each do |s|
          next if used_t.include?(s[:t_sig]) || used_d.include?(s[:d_sig])

          pairs[s[:t_sig]] = s[:d_sig]
          used_t << s[:t_sig]
          used_d << s[:d_sig]
        end

        pairs
      end

      # Build tokenized candidates from unmatched signatures.
      #
      # For each unmatched signature, extracts the body text of the
      # corresponding node, tokenizes it, and filters out nodes with
      # too few tokens for meaningful comparison.
      #
      # @param sigs [Set<Array>] Unmatched signatures
      # @param sig_map [Hash] Signature → [{node:, index:}, ...] map
      # @param analysis [FileAnalysis] Source analysis for text extraction
      # @return [Array<Hash>] Candidates with :sig, :node, :tokens keys
      def build_token_candidates(sigs, sig_map, analysis)
        candidates = []
        sigs.each do |sig|
          entries = sig_map[sig]
          next unless entries&.first

          node = entries.first[:node]
          body_text = extract_node_body_text(node, analysis)
          next if body_text.empty?

          tokens = extract_tokens(body_text, stopwords: ::Set.new, min_length: 2)
          next if tokens.size < MIN_BODY_TOKENS

          candidates << {sig: sig, node: node, tokens: tokens}
        end
        candidates
      end

      # Extract the body text of a node for Jaccard comparison.
      #
      # Only extracts body text from compound nodes that have meaningful
      # nested content (methods, classes, modules). Simple call nodes,
      # assignments, and other leaf-level nodes return empty strings
      # because their short source text leads to spurious matches.
      #
      # @param node [Prism::Node] The node to extract text from
      # @param analysis [FileAnalysis] Source analysis for line access
      # @return [String] Body text suitable for tokenization
      def extract_node_body_text(node, _analysis)
        actual = unwrap_node(node)
        case NodeTypeNormalizer.canonical_type(actual.type.to_s, :prism)
        when :def
          return "" unless actual.body

          actual.body.slice.to_s
        when :class, :module
          return "" unless actual.body

          actual.body.slice.to_s
        else
          # Leaf-level nodes (calls, assignments, etc.) are not eligible
          # for body-text similarity matching — their source text is too
          # short and leads to false positives.
          ""
        end
      end

      # ------------------------------------------------------------------
      # Phase 3: Cross-depth signature search
      # ------------------------------------------------------------------

      # Collect deep signatures only for template orphans surviving
      # Phase 1 and Phase 2.
      #
      # This narrows the expensive recursive AST walk to only the
      # signatures that are actually needed, rather than walking the
      # entire destination tree unconditionally.
      #
      # @param template_by_signature [Hash] Phase 1 template signature map
      # @param dest_sigs [Set<Array>] Phase 1 destination signatures
      # @return [Set<Array>] Signatures found at depth > 0 in the dest AST
      def compute_deep_sigs_for_orphans(template_by_signature, dest_sigs)
        template_sigs = ::Set.new(template_by_signature.keys)

        # Remove Phase 1 exact matches
        orphan_sigs = template_sigs - dest_sigs

        # Remove Phase 2 similarity matches
        orphan_sigs -= @similarity_pairs.keys if @similarity_pairs

        return ::Set.new if orphan_sigs.empty?

        # Only walk the destination AST for remaining orphans
        collect_deep_signatures(merger.dest_analysis, target_sigs: orphan_sigs)
      end

      # Recursively collect signatures from nested destination AST nodes.
      #
      # Walks into compound nodes (conditionals, begin/rescue, call blocks)
      # looking for signatures that match any of the +target_sigs+. Stops
      # early once all targets are found.
      #
      # @param analysis [FileAnalysis] Destination file analysis
      # @param target_sigs [Set<Array>, nil] If provided, only collect these
      #   signatures (early termination). If nil, collect all nested sigs.
      # @return [Set<Array>] Signatures found at depth > 0
      def collect_deep_signatures(analysis, target_sigs: nil)
        sigs = ::Set.new
        analysis.statements.each do |node|
          collect_nested_signatures(node, analysis, sigs, depth: 0, target_sigs: target_sigs)
          break if target_sigs && (target_sigs - sigs).empty?
        end
        sigs
      end

      # Walk a single node's subtree collecting signatures.
      #
      # Limits recursion to compound statement nodes where a "moved"
      # statement is semantically plausible (conditionals, begin/rescue,
      # call blocks). Does not descend into method or class definitions
      # where the same call name would have different semantics.
      #
      # @param node [Prism::Node] Current node to examine
      # @param analysis [FileAnalysis] Source analysis for signature generation
      # @param sigs [Set<Array>] Accumulator for found signatures
      # @param depth [Integer] Current recursion depth (0 = top-level)
      # @param target_sigs [Set<Array>, nil] Optional early-termination target
      # @return [void]
      def collect_nested_signatures(node, analysis, sigs, depth:, target_sigs: nil)
        actual = unwrap_node(node)
        if depth > 0
          sig = analysis.generate_signature(actual)
          if sig
            sigs << sig if target_sigs.nil? || target_sigs.include?(sig)
            return if target_sigs && (target_sigs - sigs).empty?
          end
        end

        children = nested_statement_children(actual)
        children.each do |child|
          collect_nested_signatures(child, analysis, sigs, depth: depth + 1, target_sigs: target_sigs)
          break if target_sigs && (target_sigs - sigs).empty?
        end
      end

      # Extract the immediate statement children of compound nodes.
      #
      # These are the node types where a statement might have been "moved"
      # from top-level into a nested block. The traversal is intentionally
      # limited — we do NOT descend into DefNode or ClassNode bodies, as
      # those represent distinct semantic scopes.
      #
      # @param node [Prism::Node] The compound node to inspect
      # @return [Array<Prism::Node>] Immediate statement children
      def nested_statement_children(node)
        children = []
        case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
        when :if, :unless
          children.concat(extract_body(node.statements))
          subsequent = node.respond_to?(:subsequent) ? node.subsequent : node.consequent
          children.concat(extract_body(subsequent.statements)) if subsequent.respond_to?(:statements)
          children.concat(nested_statement_children(subsequent)) if subsequent && %w[if_node else_node].include?(subsequent.type.to_s)
        when :else
          children.concat(extract_body(node.statements))
        when :begin
          children.concat(extract_body(node.statements))
          children.concat(extract_body(node.rescue_clause.statements)) if node.rescue_clause&.respond_to?(:statements)
          children.concat(extract_body(node.else_clause.statements)) if node.else_clause&.respond_to?(:statements)
          children.concat(extract_body(node.ensure_clause.statements)) if node.ensure_clause&.respond_to?(:statements)
        when :call
          if node.block && node.block.type.to_s == "block_node"
            children.concat(extract_body(node.block.body))
          end
        end
        children
      end

      # ------------------------------------------------------------------
      # Shared helpers
      # ------------------------------------------------------------------

      def comment_only_merge?
        merger.comment_only_file?(merger.template_analysis) && merger.comment_only_file?(merger.dest_analysis)
      end

      def prepare_comment_augmenters!(template_by_signature:, dest_by_signature:)
        retained = retained_owner_plan(template_by_signature: template_by_signature, dest_by_signature: dest_by_signature)

        merger.instance_variable_set(:@template_retained_owners, retained[:template])
        merger.instance_variable_set(:@dest_retained_owners, retained[:destination])
        merger.instance_variable_set(
          :@template_comment_augmenter,
          merger.template_analysis.comment_augmenter(owners: retained[:template]),
        )
        merger.instance_variable_set(
          :@dest_comment_augmenter,
          merger.dest_analysis.comment_augmenter(owners: retained[:destination]),
        )
      end

      def retained_owner_plan(template_by_signature:, dest_by_signature:)
        matched_template_indices = Set.new
        retained_dest_indices = Set.new
        sig_cursor = Hash.new(0)

        merger.dest_analysis.statements.each_with_index do |dest_node, dest_index|
          dest_signature = merger.dest_analysis.generate_signature(dest_node)
          next unless dest_signature && template_by_signature.key?(dest_signature)

          template_info, cursor = next_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor,
          )
          next unless template_info

          matched_template_indices << template_info[:index]
          retained_dest_indices << dest_index
          sig_cursor[dest_signature] = cursor + 1
        end

        merger.dest_analysis.statements.each_with_index do |_dest_node, dest_index|
          next if retained_dest_indices.include?(dest_index)
          next if merger.remove_template_missing_nodes

          retained_dest_indices << dest_index
        end

        template_retained = merger.template_analysis.statements.each_with_index.filter_map do |template_node, template_index|
          next template_node if matched_template_indices.include?(template_index)
          next template_node if merger.add_template_only_nodes

          nil
        end

        destination_retained = merger.dest_analysis.statements.each_with_index.filter_map do |dest_node, dest_index|
          dest_node if retained_dest_indices.include?(dest_index)
        end

        {
          template: template_retained,
          destination: destination_retained,
        }
      end

      def process_dest_node(dest_node:, template_by_signature:, consumed_template_indices:, sig_cursor:, output_dest_line_ranges:, last_output_dest_line:, trailing_groups: {})
        node_range = node_offset_range(dest_node)
        return last_output_dest_line if already_output?(node_range, output_dest_line_ranges)

        dest_signature = merger.dest_analysis.generate_signature(dest_node)
        last_output_dest_line = merger.send(:emit_dest_gap_lines, merger.result, merger.dest_analysis, last_output_dest_line, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis
        advance_dest_output = true

        if dest_signature && template_by_signature.key?(dest_signature)
          template_info, cursor = next_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor,
          )

          if template_info
            emission = process_matched_node(
              dest_node: dest_node,
              dest_signature: dest_signature,
              template_info: template_info,
              cursor: cursor,
              consumed_template_indices: consumed_template_indices,
              sig_cursor: sig_cursor,
              output_dest_line_ranges: output_dest_line_ranges,
              node_range: node_range,
              last_output_dest_line: last_output_dest_line,
            )
            last_output_dest_line = emission[:last_output_dest_line]
            output_node = emission[:output_node]
            output_analysis = emission[:output_analysis]

            # Emit template-only nodes that follow this matched template node
            matched_template_index = template_info[:index]
            group = trailing_groups[matched_template_index]
            group&.each do |info|
              next if consumed_template_indices.include?(info[:index])

              merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
              consumed_template_indices << info[:index]
            end
          else
            if merger.remove_template_missing_nodes
              emission = merger.send(:emit_removed_destination_node_comments, merger.result, dest_node, merger.dest_analysis)
              last_output_dest_line = emission_last_output(last_output_dest_line, emission)
              advance_dest_output = advance_dest_output?(emission)
            else
              emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
              last_output_dest_line = emission_last_output(last_output_dest_line, emission)
            end
            output_dest_line_ranges << node_range
          end
        else
          if merger.remove_template_missing_nodes
            emission = merger.send(:emit_removed_destination_node_comments, merger.result, dest_node, merger.dest_analysis)
            last_output_dest_line = emission_last_output(last_output_dest_line, emission)
            advance_dest_output = advance_dest_output?(emission)
          else
            emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
            last_output_dest_line = emission_last_output(last_output_dest_line, emission)
          end
          output_dest_line_ranges << node_range
        end

        advance_last_output_dest_line(
          last_output_dest_line: last_output_dest_line,
          dest_node: dest_node,
          output_node: output_node,
          output_analysis: output_analysis,
          advance_dest_output: advance_dest_output,
          preserve_trailing_blank_line_progress: emission&.fetch(:preserve_trailing_blank_line_progress, false),
        )
      end

      def already_output?(node_range, output_dest_line_ranges)
        output_dest_line_ranges.any? do |range|
          range[:start_offset] <= node_range[:start_offset] && node_range[:end_offset] <= range[:end_offset]
        end
      end

      def node_offset_range(node)
        location = node.location
        start_offset = if location.respond_to?(:start_offset)
          location.start_offset
        elsif node.respond_to?(:start_byte)
          node.start_byte
        else
          location.start_line
        end

        end_offset = if location.respond_to?(:end_offset)
          location.end_offset
        elsif node.respond_to?(:end_byte)
          node.end_byte
        else
          location.end_line
        end

        {
          start_offset: start_offset,
          end_offset: end_offset,
        }
      end

      def next_template_match(candidates:, signature:, sig_cursor:)
        cursor = sig_cursor[signature]

        candidate = candidates[cursor]
        return [candidate, cursor] if candidate

        [nil, cursor]
      end

      def process_matched_node(dest_node:, dest_signature:, template_info:, cursor:, consumed_template_indices:, sig_cursor:, output_dest_line_ranges:, node_range:, last_output_dest_line:)
        template_node = template_info[:node]
        consumed_template_indices << template_info[:index]
        sig_cursor[dest_signature] = cursor + 1
        output_dest_line_ranges << node_range

        if merger.send(:should_merge_recursively?, template_node, dest_node)
          process_recursive_match(
            template_node: template_node,
            dest_node: dest_node,
            last_output_dest_line: last_output_dest_line,
          )
        else
          process_non_recursive_match(
            template_node: template_node,
            dest_node: dest_node,
            last_output_dest_line: last_output_dest_line,
          )
        end
      end

      def process_recursive_match(template_node:, dest_node:, last_output_dest_line:)
        recursive_emission = merger.send(:merge_node_body_recursively, template_node, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis

        if merger.send(:preference_for_node, template_node, dest_node) == :template
          output_node = unwrap_node(template_node)
          output_analysis = merger.template_analysis
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, recursive_emission),
          output_node: output_node,
          output_analysis: output_analysis,
          preserve_trailing_blank_line_progress: true,
        }
      end

      def process_non_recursive_match(template_node:, dest_node:, last_output_dest_line:)
        output_node = dest_node
        output_analysis = merger.dest_analysis
        emission = nil

        if merger.send(:preference_for_node, template_node, dest_node) == :template
          emission = merger.send(:add_matched_template_node_to_result, merger.result, template_node, dest_node)
          output_node = template_node
          output_analysis = merger.template_analysis
        else
          emission = merger.send(
            :add_node_to_result,
            merger.result,
            dest_node,
            merger.dest_analysis,
            :destination,
            matched_template_node: template_node,
          )
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, emission),
          output_node: output_node,
          output_analysis: output_analysis,
          preserve_trailing_blank_line_progress: emission&.fetch(:preserve_trailing_blank_line_progress, false),
        }
      end

      def emission_last_output(last_output_dest_line, emission)
        emitted_dest_line = emission&.dig(:last_emitted_dest_line)
        return last_output_dest_line unless emitted_dest_line

        [last_output_dest_line, emitted_dest_line].max
      end

      def advance_last_output_dest_line(last_output_dest_line:, dest_node:, output_node:, output_analysis:, advance_dest_output: true, preserve_trailing_blank_line_progress: false)
        return last_output_dest_line unless advance_dest_output

        updated_last_output_dest_line = [last_output_dest_line, dest_node.location.end_line].max

        return updated_last_output_dest_line unless preserve_trailing_blank_line_progress

        actual_output_end = unwrap_node(output_node).location.end_line
        trailing_line_num = actual_output_end + 1
        trailing_content = output_analysis.line_at(trailing_line_num)
        return updated_last_output_dest_line unless trailing_content && trailing_content.strip.empty?

        trailing_dest_line = dest_node.location.end_line + 1
        dest_trailing = merger.dest_analysis.line_at(trailing_dest_line)
        return updated_last_output_dest_line unless dest_trailing && dest_trailing.strip.empty?

        [updated_last_output_dest_line, trailing_dest_line].max
      end

      def advance_dest_output?(emission)
        !emission&.fetch(:emitted_removed_owner_comments, false)
      end

      def emit_dest_postlude_lines(last_output_dest_line)
        postlude_gap = merger.dest_analysis.layout_augmenter.postlude_gap
        if postlude_gap
          emit_dest_blank_lines(([postlude_gap.start_line, last_output_dest_line + 1].max)..postlude_gap.end_line)
          return
        end

        remaining_line_range = (last_output_dest_line + 1)..merger.dest_analysis.lines.length
        emit_dest_blank_lines(remaining_line_range)
      end

      def emit_dest_blank_lines(line_range)
        return if line_range.begin > line_range.end

        line_range.each do |line_num|
          line = merger.dest_analysis.line_at(line_num).to_s.chomp
          next unless line.strip.empty?

          merger.result.add_line(
            line,
            decision: MergeResult::DECISION_KEPT_DEST,
            dest_line: line_num,
          )
        end
      end

      def unwrap_node(node)
        node.respond_to?(:unwrap) ? node.unwrap : node
      end

      # Extract body statements from a StatementsNode or similar container.
      #
      # @param statements_node [Prism::StatementsNode, #body, nil]
      # @return [Array<Prism::Node>]
      def extract_body(statements_node)
        return [] unless statements_node

        if statements_node.type.to_s == "statements_node"
          statements_node.body.compact
        elsif statements_node.respond_to?(:body)
          Array(statements_node.body).compact
        else
          []
        end
      end
    end
  end
end
