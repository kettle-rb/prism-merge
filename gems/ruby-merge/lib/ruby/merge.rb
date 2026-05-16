# frozen_string_literal: true

require "tree_haver"
require "ast/merge"

module Ruby
  module Merge
    extend self

    PACKAGE_NAME = "ruby-merge"
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: "array", name: "destination_wins_array" }.freeze
    DIRECTIVE_LINE = /\A(?::nocov:|[\w-]+:(?:freeze|unfreeze))\z/
    MAGIC_COMMENT_PREFIXES = %w[coding encoding frozen_string_literal shareable_constant_value typed warn_indent].freeze
    REQUIRE_PATTERN = /^\s*require(?:_relative)?\s+["']([^"']+)["']/.freeze
    DSL_CALL_PATTERN = /^(?<name>source|gemspec|git_source|gem|eval_gemfile|platform|group|desc|task)\b/.freeze
    RAKEFILE_DEFAULT_TASK_COMMENT = "# Define a base default task early so other files can enhance it."
    RAKEFILE_DEFAULT_TASK_DESC = 'desc "Default tasks aggregator"'
    CLASS_PATTERN = /^\s*class\s+([A-Z]\w*(?:::\w+)*)/.freeze
    MODULE_PATTERN = /^\s*module\s+([A-Z]\w*(?:::\w+)*)/.freeze
    DEF_PATTERN = /^\s*def\s+((?:self\.)?)([a-zA-Z_]\w*[!?=]?|\[\]=?|\+@|-@|\*\*|<<|>>|<=>|===|==|=~|!~|!=|[+\-*\/%&|^<>]=?|[!~`])/.freeze
    CONSTANT_ASSIGNMENT_PATTERN = /^(\s*)([A-Z]\w*)\s*=/.freeze
    CONSTANT_HASH_ASSIGNMENT_PATTERN = /^(\s*)([A-Z]\w*)\s*=\s*\{/.freeze
    EXAMPLE_TAG = /\A@example\b(?<rest>.*)\z/.freeze
    TAG_PREFIX = /\A@[a-z_]+\b/.freeze

    def ruby_feature_profile
      {
        family: "ruby",
        supported_dialects: ["ruby"],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def available_ruby_backends
      [TREE_SITTER_BACKEND]
    end

    def ruby_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == TREE_SITTER_BACKEND.id

      ruby_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
    end

    def ruby_plan_context(backend: nil)
      profile = ruby_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: ruby_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_ruby(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == TREE_SITTER_BACKEND.id

      syntax = TreeHaver.parse_with_language_pack(
        TreeHaver::ParserRequest.new(source: source, language: "ruby", dialect: dialect)
      )
      return { ok: false, diagnostics: syntax[:diagnostics], policies: [] } unless syntax[:ok]

      {
        ok: true,
        diagnostics: [],
        analysis: analyze_ruby_document(source),
        policies: []
      }
    end

    def match_ruby_owners(template, destination)
      destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
      template_paths = template[:owners].to_h { |owner| [owner[:path], true] }
      {
        matched: template[:owners]
          .filter { |owner| destination_paths[owner[:path]] }
          .map { |owner| { template_path: owner[:path], destination_path: owner[:path] } },
        unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
        unmatched_destination: destination[:owners].map { |owner| owner[:path] }.reject { |path| template_paths[path] }
      }
    end

    def ruby_method_move_detection(template_source, destination_source, dialect)
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"

      template_methods = ruby_method_projection(template_source, revision: "template")
      destination_methods = ruby_method_projection(destination_source, revision: "destination")
      destination_by_signature = destination_methods.to_h { |entry| [entry[:signature], entry] }
      template_signatures = template_methods.map { |entry| entry[:signature] }.to_h { |signature| [signature, true] }

      matches = template_methods.filter_map do |template_entry|
        destination_entry = destination_by_signature[template_entry[:signature]]
        next unless destination_entry

        moved = template_entry[:index] != destination_entry[:index] || template_entry[:parent_path] != destination_entry[:parent_path]
        Ast::Merge::MoveDetectionMatch.new(
          from_path: template_entry[:path],
          to_path: destination_entry[:path],
          from_node_id: template_entry[:node_id],
          to_node_id: destination_entry[:node_id],
          signature: template_entry[:signature],
          moved: moved,
          from_parent_path: template_entry[:parent_path],
          to_parent_path: destination_entry[:parent_path],
          from_index: template_entry[:index],
          to_index: destination_entry[:index],
          confidence: moved ? 0.98 : 0.9,
          diagnostics: [moved ? "same Ruby method signature observed at a different sibling position" : "same Ruby method signature observed at the same sibling position"]
        )
      end

      matched_template_signatures = matches.map(&:signature).to_h { |signature| [signature, true] }
      Ast::Merge::MoveDetectionMatchingReport.new(
        matching_id: "ruby-method-move-detection",
        strategy: "move_detection",
        from_revision: "template",
        to_revision: "destination",
        capability: Ast::Merge::MoveDetectionCapability.new(
          name: "move_detection",
          enabled: true,
          default_enabled: false,
          requires_stable_node_identity: true
        ),
        matches: matches,
        unmatched_from: template_methods.reject { |entry| matched_template_signatures[entry[:signature]] }.map { |entry| entry[:path] },
        unmatched_to: destination_methods.reject { |entry| template_signatures[entry[:signature]] }.map { |entry| entry[:path] },
        diagnostics: ["Ruby method move detection uses generic move-detection matching over receiver-aware method projections"]
      ).to_h
    end

    def merge_ruby(template_source, destination_source, dialect, merge_template_requires: false)
      template = parse_ruby(template_source, dialect)
      return template unless template[:ok]

      destination = parse_ruby(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == "parse_error" ? diagnostic.merge(category: "destination_parse_error") : diagnostic
          end,
          policies: []
        }
      end

      destination_requires = collect_ruby_require_entries(destination.dig(:analysis, :source))
      template_requires = collect_ruby_require_entries(template.dig(:analysis, :source))
      destination_declarations = collect_ruby_declaration_entries(destination.dig(:analysis, :source))
      template_declarations = collect_ruby_declaration_entries(template.dig(:analysis, :source))
      template_declaration_candidates = template_declarations + qualified_nested_declaration_entries(template_declarations)
      destination_paths = destination_declarations.to_h { |entry| [entry[:merge_key], true] }
      template_declarations_by_path = template_declaration_candidates.to_h { |entry| [entry[:merge_key], entry] }
      destination_dsl = collect_top_level_dsl_entries(destination.dig(:analysis, :source))
      template_dsl = collect_top_level_dsl_entries(template.dig(:analysis, :source))
      sections = []
      preamble = collect_ruby_preamble(destination.dig(:analysis, :source))
      sections << preamble unless preamble.empty?
      requires = merge_template_requires ? merge_ruby_requires(destination_requires, template_requires) : destination_requires
      require_block = requires.map { |entry| entry[:text] }.join("\n").strip
      sections << require_block unless require_block.empty?
      sections.concat(merge_top_level_dsl_entries(destination_dsl, template_dsl).map { |entry| entry[:text] })
      matched_template_declarations = {}
      sections.concat(
        destination_declarations.map do |entry|
          template_entry = template_declarations_by_path[entry[:merge_key]]
          matched_template_declarations[template_entry[:merge_key]] = true if template_entry
          merge_ruby_declaration_entry(template_entry, entry)[:text]
        end
      )
      sections.concat(
        template_declarations.reject do |entry|
          destination_paths[entry[:merge_key]] || namespace_wrapper_matched?(entry, template_declaration_candidates, matched_template_declarations)
        end.map { |entry| entry[:text] }
      )

      output = "#{sections.join("\n\n").strip}\n"

      {
        ok: true,
        diagnostics: [],
        output: normalize_rakefile_default_task_scaffold(output),
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def ruby_discovered_surfaces(analysis)
      analysis[:discovered_surfaces] || []
    end

    def ruby_delegated_child_operations(analysis, parent_operation_id: "ruby-document-0")
      surfaces = ruby_discovered_surfaces(analysis)
      doc_operation_ids = {}
      operations = []

      surfaces.each_with_index do |surface, index|
        next unless surface[:surface_kind] == "ruby_doc_comment"

        operation_id = "ruby-doc-comment-#{index}"
        doc_operation_ids[surface[:address]] = operation_id
        operations << Ast::Merge.delegated_child_operation(
          operation_id: operation_id,
          parent_operation_id: parent_operation_id,
          requested_strategy: "delegate_child_surface",
          language_chain: ["ruby", surface[:effective_language]],
          surface: surface
        )
      end

      example_index = 0
      surfaces.each do |surface|
        next unless surface[:surface_kind] == "yard_example_block"

        operations << Ast::Merge.delegated_child_operation(
          operation_id: "yard-example-#{example_index}",
          parent_operation_id: doc_operation_ids.fetch(surface[:parent_address], parent_operation_id),
          requested_strategy: "delegate_child_surface",
          language_chain: ["ruby", "yard", surface[:effective_language]],
          surface: surface
        )
        example_index += 1
      end

      operations
    end

    def apply_ruby_delegated_child_outputs(source, delegated_operations, apply_plan, applied_children)
      lines = normalize_source(source).split("\n")
      operations_by_id = delegated_operations.to_h { |operation| [operation[:operation_id], operation] }
      outputs_by_id = applied_children.to_h { |entry| [entry[:operation_id], entry[:output]] }

      replacements = apply_plan[:entries].filter_map do |entry|
        operation = operations_by_id[entry.dig(:delegated_group, :child_operation_id)]
        output = outputs_by_id[entry.dig(:delegated_group, :child_operation_id)]
        span = operation&.dig(:surface, :span)
        next if operation.nil? || output.nil? || span.nil?

        { start: span[:start_line] - 1, finish: span[:end_line] - 1, output: output }
      end

      replacements.sort_by { |entry| -entry[:start] }.each do |entry|
        prefix = comment_prefix_for(lines[entry[:start]])
        replacement_lines = entry[:output].empty? ? [] : entry[:output].sub(/\n\z/, "").split("\n").map { |line| "#{prefix}#{line}" }
        lines[entry[:start]..entry[:finish]] = replacement_lines
      end

      {
        ok: true,
        diagnostics: [],
        output: "#{lines.join("\n").sub(/\n+\z/, "")}\n",
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def merge_ruby_with_nested_outputs(template_source, destination_source, dialect, nested_outputs)
      Ast::Merge.execute_nested_merge(
        nested_outputs,
        default_family: "ruby",
        request_id_prefix: "nested_ruby_child",
        merge_parent: -> { merge_ruby(template_source, destination_source, dialect) },
        discover_operations: lambda { |merged_output|
          analysis = parse_ruby(merged_output, dialect)
          next { ok: false, diagnostics: analysis[:diagnostics] || [] } unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: ruby_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, applied_children|
          apply_ruby_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            applied_children
          )
        }
      )
    end

    def merge_ruby_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state, applied_children)
      Ast::Merge.execute_reviewed_nested_merge(
        review_state,
        "ruby",
        applied_children,
        merge_parent: -> { merge_ruby(template_source, destination_source, dialect) },
        discover_operations: lambda { |merged_output|
          analysis = parse_ruby(merged_output, dialect)
          next({ ok: false, diagnostics: analysis[:diagnostics] || [] }) unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: ruby_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, resolved_children|
          apply_ruby_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            resolved_children
          )
        }
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect, replay_bundle)
      execution = Array(replay_bundle[:reviewed_nested_executions]).find { |entry| entry[:family] == "ruby" }
      return { ok: false, diagnostics: [{ severity: "error", category: "configuration_error", message: "review replay bundle does not include a reviewed nested execution for ruby." }], policies: [] } unless execution

      merge_ruby_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        execution[:review_state],
        execution[:applied_children]
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect, review_state)
      execution = Array(review_state[:reviewed_nested_executions]).find { |entry| entry[:family] == "ruby" }
      return { ok: false, diagnostics: [{ severity: "error", category: "configuration_error", message: "review state does not include a reviewed nested execution for ruby." }], policies: [] } unless execution

      merge_ruby_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        execution[:review_state],
        execution[:applied_children]
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source, dialect, envelope)
      replay_bundle, import_error = Ast::Merge.import_review_replay_bundle_envelope(envelope)
      return { ok: false, diagnostics: [{ severity: "error", category: import_error[:category], message: import_error[:message] }], policies: [] } if import_error

      merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source, dialect, envelope)
      review_state, import_error = Ast::Merge.import_conformance_manifest_review_state_envelope(envelope)
      return { ok: false, diagnostics: [{ severity: "error", category: import_error[:category], message: import_error[:message] }], policies: [] } if import_error

      merge_ruby_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state
      )
    end

    def analyze_ruby_document(source)
      lines = normalize_source(source).split("\n", -1)
      requires = []
      declarations = []
      discovered_surfaces = []
      pending_comments = []

      lines.each_with_index do |line, index|
        line_number = index + 1
        stripped = line.strip

        if comment_line?(line)
          pending_comments << { line: line_number, raw: line }
          next
        end

        if stripped.empty?
          pending_comments = []
          next
        end

        if (match = REQUIRE_PATTERN.match(line))
          requires << {
            path: "/requires/#{requires.length}",
            owner_kind: "require",
            match_key: match[1]
          }
          pending_comments = []
          next
        end

        declaration = declaration_for_line(line)
        if declaration
          declarations << {
            path: "/declarations/#{declaration[:name]}",
            owner_kind: "declaration",
            match_key: declaration[:name]
          }
          surfaces = surfaces_for_owner(
            owner_name: declaration[:name],
            comment_entries: pending_comments
          )
          discovered_surfaces.concat(surfaces)
          pending_comments = []
          next
        end

        pending_comments = []
      end

      {
        kind: "ruby",
        dialect: "ruby",
        root_kind: "document",
        source: normalize_source(source),
        owners: (requires + declarations).sort_by { |owner| owner[:path] },
        discovered_surfaces: discovered_surfaces,
        method_shadowing: ruby_method_shadowing(source),
        diagnostics: ruby_method_shadowing_diagnostics(source)
      }
    end

    def collect_ruby_require_entries(source)
      normalize_source(source).split("\n").filter_map do |line|
        match = REQUIRE_PATTERN.match(line)
        next unless match

        { path: "/requires/#{match[1]}", text: line.rstrip }
      end
    end

    def collect_ruby_preamble(source)
      lines = normalize_source(source).split("\n")
      preamble = []
      lines.each do |line|
        break unless line.strip.empty? || comment_line?(line)

        preamble << line.rstrip
      end
      preamble.join("\n").strip
    end

    def collect_top_level_dsl_entries(source)
      lines = normalize_source(source).split("\n")
      entries = []
      pending_comments = []
      index = 0

      while index < lines.length
        line = lines[index]
        stripped = line.strip
        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end
        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end
        if REQUIRE_PATTERN.match?(line) || declaration_for_line(line)
          pending_comments = []
          index += 1
          next
        end

        if line.match?(/\Abegin\b/)
          start_index = pending_comments.first || index
          finish_index = ruby_block_finish_index(lines, index)
          text = lines[start_index..finish_index].join("\n").strip
          signature = begin_block_signature(text)
          entries << { path: "/dsl/#{signature}", name: "begin", signature: signature, text: text }
          pending_comments = []
          index = finish_index + 1
          next
        end

        match = DSL_CALL_PATTERN.match(line)
        unless match
          pending_comments = []
          index += 1
          next
        end

        name = match[:name]
        if name == "desc" && next_code_line_is_task?(lines, index + 1)
          pending_comments << index
          index += 1
          next
        end

        start_index = pending_comments.first || index
        finish_index = dsl_entry_finish_index(lines, index)
        text = lines[start_index..finish_index].join("\n").strip
        signature = dsl_entry_signature(name, line)
        entries << { path: "/dsl/#{signature}", name: name, signature: signature, text: text } if signature
        pending_comments = []
        index = finish_index + 1
      end

      entries
    end

    def merge_top_level_dsl_entries(destination_entries, template_entries)
      destination_by_signature = destination_entries.to_h { |entry| [entry[:signature], entry] }
      template_singletons = template_entries.select { |entry| dsl_singleton_entry?(entry) }
      template_singleton_signatures = template_singletons.map { |entry| entry[:signature] }.to_h { |signature| [signature, true] }
      result = []
      result.concat(template_singletons)
      result.concat(destination_entries.reject { |entry| template_singleton_signatures[entry[:signature]] })
      result.concat(
        template_entries.reject do |entry|
          dsl_singleton_entry?(entry) || destination_by_signature[entry[:signature]]
        end
      )
      result
    end

    def merge_ruby_requires(destination_requires, template_requires)
      destination_paths = destination_requires.to_h { |entry| [entry[:path], true] }
      destination_requires + template_requires.reject { |entry| destination_paths[entry[:path]] }
    end

    def collect_ruby_declaration_entries(source)
      lines = normalize_source(source).split("\n")
      entries = []
      pending_comments = []
      index = 0

      while index < lines.length
        line = lines[index]
        stripped = line.strip

        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        if REQUIRE_PATTERN.match?(line)
          pending_comments = []
          index += 1
          next
        end

        declaration = declaration_for_line(line)
        unless declaration
          pending_comments = []
          index += 1
          next
        end

        start_index = pending_comments.first || index
        depth = 1
        cursor = index + 1
        while cursor < lines.length
          candidate = lines[cursor].strip
          depth += 1 if declaration_for_line(candidate)
          if candidate == "end"
            depth -= 1
            if depth.zero?
              cursor += 1
              break
            end
          end
          cursor += 1
        end

        entries << {
          path: "/declarations/#{declaration[:name]}",
          name: declaration[:name],
          kind: declaration[:kind],
          merge_key: "#{declaration[:kind]}:#{declaration[:name]}",
          text: lines[start_index...cursor].join("\n").strip
        }
        pending_comments = []
        index = cursor
      end

      entries
    end

    def merge_ruby_declaration_entry(template_entry, destination_entry)
      return destination_entry unless template_entry

      merged_text = merge_declaration_hash_constants(template_entry[:text], destination_entry[:text])
      merged_text = merge_declaration_body_constants(template_entry[:text], merged_text)
      merged_text = merge_declaration_body_methods(template_entry[:text], merged_text)
      merged_text = merge_nested_body_declarations(template_entry[:text], merged_text)
      destination_entry.merge(
        text: merged_text
      )
    end

    def ruby_method_shadowing(source)
      collect_ruby_declaration_entries(source).flat_map do |entry|
        direct_method_shadowing(entry)
      end
    end

    def ruby_method_shadowing_diagnostics(source)
      ruby_method_shadowing(source).map do |entry|
        {
          severity: "warning",
          category: "ruby_method_shadowing",
          path: "#{entry[:owner_path]}/methods/#{entry[:method_signature]}",
          message: "Ruby method #{entry[:method_signature]} is defined #{entry[:shadowed_count] + 1} times in #{entry[:owner_path]}; the last definition shadows earlier definitions."
        }
      end
    end

    def direct_method_shadowing(declaration_entry)
      grouped = direct_body_method_entries(declaration_entry[:text]).each_with_index.group_by do |(method_entry, _index)|
        method_entry[:signature]
      end

      grouped.filter_map do |signature, entries|
        next if entries.length < 2

        {
          owner_path: declaration_entry[:path],
          method_signature: signature,
          effective_index: entries.last[1],
          shadowed_indices: entries[0...-1].map { |_method_entry, index| index },
          shadowed_count: entries.length - 1
        }
      end
    end

    def ruby_method_projection(source, revision:)
      collect_ruby_declaration_entries(source).flat_map do |declaration_entry|
        direct_body_method_entries(declaration_entry[:text]).each_with_index.map do |method_entry, index|
          signature = "method:#{declaration_entry[:path]}:#{method_entry[:signature]}"
          {
            path: "#{declaration_entry[:path]}/methods/#{index}",
            parent_path: "#{declaration_entry[:path]}/methods",
            node_id: "#{revision}:#{signature}",
            signature: signature,
            index: index
          }
        end
      end
    end

    def qualified_nested_declaration_entries(entries)
      entries.flat_map do |entry|
        direct_body_declaration_entries(entry[:text]).map do |nested_entry|
          root_name = entry[:name]
          nested_name = nested_entry[:name]
          qualified_name = nested_name.include?("::") ? nested_name : "#{root_name}::#{nested_name}"
          nested_entry.merge(
            name: qualified_name,
            path: "/declarations/#{qualified_name}",
            merge_key: "#{nested_entry[:kind]}:#{qualified_name}",
            text: normalize_declaration_text_indent(nested_entry[:text]),
            namespace_root_merge_key: entry[:merge_key]
          )
        end
      end
    end

    def normalize_declaration_text_indent(text)
      lines = text.to_s.split("\n")
      base_indent = lines.first.to_s[/\A\s*/].to_s
      return text if base_indent.empty?

      lines.map do |line|
        line.start_with?(base_indent) ? line[base_indent.length..].to_s : line
      end.join("\n")
    end

    def namespace_wrapper_matched?(entry, candidates, matched)
      children = candidates.select { |candidate| candidate[:namespace_root_merge_key] == entry[:merge_key] }
      return false if children.empty?
      return false unless direct_body_method_entries(entry[:text]).empty? && direct_body_constant_entries(entry[:text]).empty?

      children.all? { |child| matched[child[:merge_key]] }
    end

    def merge_declaration_hash_constants(template_text, destination_text)
      template_blocks = constant_hash_blocks(template_text).to_h { |block| [block[:constant], block] }
      destination_blocks = constant_hash_blocks(destination_text)
      return destination_text if template_blocks.empty? || destination_blocks.empty?

      output = destination_text.dup
      destination_blocks.reverse_each do |destination_block|
        template_block = template_blocks[destination_block[:constant]]
        next unless template_block

        template_hash = RubyHashLiteralParser.new(template_block[:hash_source]).parse
        destination_hash = RubyHashLiteralParser.new(destination_block[:hash_source]).parse
        merged_hash = merge_ruby_hash_literals(template_hash, destination_hash)
        rendered = "#{destination_block[:prefix]}#{render_ruby_hash_literal(merged_hash, destination_block[:base_indent])}"
        output[destination_block[:range]] = rendered
      rescue ArgumentError
        next
      end
      output
    end

    def merge_declaration_body_constants(template_text, destination_text)
      template_constants = direct_body_constant_entries(template_text)
      destination_constants = direct_body_constant_entries(destination_text)
      return destination_text if template_constants.empty?

      merged_text = merge_matched_array_constants(template_constants, destination_constants, destination_text)
      destination_names = destination_constants.map { |entry| entry[:name] }.to_h { |name| [name, true] }
      missing_constants = template_constants.reject { |entry| destination_names[entry[:name]] }
      return merged_text if missing_constants.empty?

      insert_declaration_body_blocks(merged_text, missing_constants.map { |entry| entry[:text] }, placement: :after_opening)
    end

    def merge_matched_array_constants(template_constants, destination_constants, destination_text)
      template_by_name = template_constants.to_h { |entry| [entry[:name], entry] }
      output = destination_text.dup
      destination_constants.reverse_each do |destination_entry|
        template_entry = template_by_name[destination_entry[:name]]
        next unless template_entry

        merged_text = merge_array_constant_text(template_entry[:text], destination_entry[:text])
        next unless merged_text

        output[destination_entry[:range]] = merged_text
      end
      output
    end

    def merge_array_constant_text(template_text, destination_text)
      template_match = template_text.match(/\A(\s*[A-Z]\w*\s*=\s*)\[(.*)\]\z/)
      destination_match = destination_text.match(/\A(\s*[A-Z]\w*\s*=\s*)\[(.*)\]\z/)
      return merge_percent_array_constant_text(template_text, destination_text) || merge_multiline_array_constant_text(template_text, destination_text) unless template_match && destination_match

      destination_elements = split_ruby_array_elements(destination_match[2])
      template_elements = split_ruby_array_elements(template_match[2])
      destination_keys = destination_elements.map { |element| normalize_array_element_key(element) }.to_h { |key| [key, true] }
      appended = template_elements.reject { |element| destination_keys[normalize_array_element_key(element)] }
      return destination_text if appended.empty?

      "#{destination_match[1]}[#{(destination_elements + appended).join(", ")}]"
    end

    def merge_percent_array_constant_text(template_text, destination_text)
      template_match = template_text.match(/\A(\s*[A-Z]\w*\s*=\s*%[wi]\[)(.*)(\])\z/)
      destination_match = destination_text.match(/\A(\s*[A-Z]\w*\s*=\s*%[wi]\[)(.*)(\])\z/)
      return unless template_match && destination_match

      destination_elements = destination_match[2].split(/\s+/).reject(&:empty?)
      template_elements = template_match[2].split(/\s+/).reject(&:empty?)
      destination_keys = destination_elements.to_h { |element| [element, true] }
      appended = template_elements.reject { |element| destination_keys[element] }
      return destination_text if appended.empty?

      "#{destination_match[1]}#{(destination_elements + appended).join(" ")}#{destination_match[3]}"
    end

    def merge_multiline_array_constant_text(template_text, destination_text)
      template_match = template_text.match(/\A(\s*[A-Z]\w*\s*=\s*\[\n)(.*)(\n\s*\])\z/m)
      destination_match = destination_text.match(/\A(\s*[A-Z]\w*\s*=\s*\[\n)(.*)(\n\s*\])\z/m)
      return unless template_match && destination_match

      destination_elements = multiline_array_elements(destination_match[2])
      template_elements = multiline_array_elements(template_match[2])
      destination_keys = destination_elements.map { |element| normalize_array_element_key(element[:value]) }.to_h { |key| [key, true] }
      appended = template_elements.reject { |element| destination_keys[normalize_array_element_key(element[:value])] }
      return destination_text if appended.empty?

      insertion_prefix = destination_elements.last&.dig(:indent) || template_elements.first&.dig(:indent) || "  "
      body = append_multiline_array_elements(destination_match[2], appended, insertion_prefix)
      "#{destination_match[1]}#{body}#{destination_match[3]}"
    end

    def merge_declaration_body_methods(template_text, destination_text)
      template_methods = direct_body_method_entries(template_text)
      destination_methods = direct_body_method_entries(destination_text)
      return destination_text if template_methods.empty?

      destination_method_signatures = destination_methods.map { |entry| entry[:signature] }.to_h { |signature| [signature, true] }
      missing_methods = template_methods.reject { |entry| destination_method_signatures[entry[:signature]] }
      return destination_text if missing_methods.empty?

      public_methods, visibility_methods = missing_methods.partition { |entry| entry[:visibility] == "public" }
      merged_text = destination_text
      unless public_methods.empty?
        merged_text = insert_declaration_body_blocks(
          merged_text,
          public_methods.map { |entry| entry[:body_text] },
          before_visibility: !direct_visibility_section_present?(merged_text, "public")
        )
      end
      visibility_methods.group_by { |entry| entry[:visibility] }.each do |visibility, entries|
        blocks = if direct_visibility_section_present?(merged_text, visibility)
          merged_text = insert_declaration_body_blocks(merged_text, entries.map { |entry| entry[:body_text] }, before_visibility: false)
          next
        else
          entries.map { |entry| entry[:text] }
        end
        merged_text = insert_declaration_body_blocks(merged_text, blocks)
      end
      merged_text
    end

    def merge_nested_body_declarations(template_text, destination_text)
      template_entries = direct_body_declaration_entries(template_text)
      destination_entries = direct_body_declaration_entries(destination_text)
      return destination_text if template_entries.empty? || destination_entries.empty?

      template_by_path = template_entries.to_h { |entry| [entry[:merge_key], entry] }
      output = destination_text.dup
      destination_entries.reverse_each do |destination_entry|
        template_entry = template_by_path[destination_entry[:merge_key]]
        next unless template_entry

        output[destination_entry[:range]] = merge_ruby_declaration_entry(template_entry, destination_entry)[:text]
      end

      destination_paths = destination_entries.map { |entry| entry[:merge_key] }.to_h { |path| [path, true] }
      missing_entries = template_entries.reject { |entry| destination_paths[entry[:merge_key]] }
      return output if missing_entries.empty?

      insert_declaration_body_blocks(output, missing_entries.map { |entry| entry[:text] })
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }],
        policies: []
      }
    end

    private

    RubyHashNode = Struct.new(:pairs, :inline, keyword_init: true)
    RubyHashPair = Struct.new(:key, :value, keyword_init: true)
    RubyScalarNode = Struct.new(:source, keyword_init: true)

    class RubyHashLiteralParser
      def initialize(source)
        @source = source.to_s
        @index = 0
      end

      def parse
        parse_hash.tap do
          skip_whitespace
          raise ArgumentError, "unexpected trailing hash literal content" unless eof?
        end
      end

      private

      attr_reader :source

      def parse_hash
        start_index = @index
        consume("{")
        pairs = []
        loop do
          skip_whitespace
          break if peek == "}"

          key = parse_symbol_key
          skip_whitespace
          value = parse_value
          pairs << RubyHashPair.new(key: key, value: value)
          skip_whitespace
          break if peek == "}"

          consume(",")
        end
        consume("}")
        RubyHashNode.new(pairs: pairs, inline: !source[start_index...@index].include?("\n"))
      end

      def parse_value
        skip_whitespace
        return parse_hash if peek == "{"

        RubyScalarNode.new(source: parse_scalar_source)
      end

      def parse_symbol_key
        match = source[@index..].to_s.match(/\A([a-zA-Z_]\w*):/)
        raise ArgumentError, "expected symbol hash key" unless match

        @index += match[0].length
        match[1]
      end

      def parse_scalar_source
        start_index = @index
        string_quote = nil
        escape = false
        while @index < source.length
          char = source[@index]
          if string_quote
            if escape
              escape = false
            elsif char == "\\"
              escape = true
            elsif char == string_quote
              string_quote = nil
            end
            @index += 1
            next
          end

          break if char == "," || char == "}"
          string_quote = char if char == "\"" || char == "'"
          @index += 1
        end
        source[start_index...@index].rstrip
      end

      def skip_whitespace
        @index += 1 while @index < source.length && source[@index].match?(/\s/)
      end

      def consume(expected)
        raise ArgumentError, "expected #{expected}" unless peek == expected

        @index += 1
      end

      def peek
        source[@index]
      end

      def eof?
        @index >= source.length
      end
    end

    def constant_hash_blocks(text)
      lines = text.to_s.split("\n", -1)
      line_start_offsets = []
      offset = 0
      lines.each do |line|
        line_start_offsets << offset
        offset += line.length + 1
      end

      blocks = []
      index = 0
      while index < lines.length
        line = lines[index]
        match = CONSTANT_HASH_ASSIGNMENT_PATTERN.match(line)
        unless match
          index += 1
          next
        end

        start_line = index
        finish_line = hash_assignment_finish_line(lines, start_line)
        if finish_line
          block_source = lines[start_line..finish_line].join("\n")
          hash_offset = block_source.index("{")
          start_offset = line_start_offsets[start_line]
          finish_offset = line_start_offsets[finish_line] + lines[finish_line].length
          blocks << {
            constant: match[2],
            prefix: block_source[0...hash_offset],
            hash_source: block_source[hash_offset..],
            base_indent: match[1].length,
            range: (start_offset...finish_offset)
          }
          index = finish_line + 1
        else
          index += 1
        end
      end
      blocks
    end

    def hash_assignment_finish_line(lines, start_line)
      depth = 0
      in_string = nil
      escape = false
      start_line.upto(lines.length - 1) do |line_index|
        lines[line_index].each_char do |char|
          if in_string
            if escape
              escape = false
            elsif char == "\\"
              escape = true
            elsif char == in_string
              in_string = nil
            end
            next
          end

          if char == "\"" || char == "'"
            in_string = char
          elsif char == "{"
            depth += 1
          elsif char == "}"
            depth -= 1
            return line_index if depth.zero?
          end
        end
      end
      nil
    end

    def direct_body_method_entries(text)
      lines = text.to_s.split("\n")
      return [] if lines.length < 3

      entries = []
      pending_comments = []
      current_visibility = "public"
      visibility_start_index = nil
      visibility_consumed = false
      index = 1
      while index < lines.length - 1
        line = lines[index]
        stripped = line.strip
        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        if %w[private protected public].include?(stripped)
          current_visibility = stripped
          visibility_start_index = index
          visibility_consumed = false
          pending_comments = []
          index += 1
          next
        end

        nested_declaration = declaration_for_line(line)
        if nested_declaration && %w[class module].include?(nested_declaration[:kind])
          pending_comments = []
          index = ruby_block_finish_index(lines, index) + 1
          next
        end

        match = DEF_PATTERN.match(line)
        unless match
          pending_comments = []
          index += 1
          next
        end

        start_index = pending_comments.first || visibility_section_start_index(visibility_start_index, visibility_consumed) || index
        finish_index = ruby_block_finish_index(lines, index)
        entries << {
          name: match[2],
          signature: "#{match[1]}#{match[2]}",
          visibility: current_visibility,
          text: lines[start_index..finish_index].join("\n").rstrip,
          body_text: lines[(pending_comments.first || index)..finish_index].join("\n").rstrip
        }
        pending_comments = []
        visibility_consumed = true
        index = finish_index + 1
      end
      entries
    end

    def direct_body_constant_entries(text)
      lines = text.to_s.split("\n")
      return [] if lines.length < 3

      line_start_offsets = []
      offset = 0
      lines.each do |line|
        line_start_offsets << offset
        offset += line.length + 1
      end

      entries = []
      index = 1
      while index < lines.length - 1
        stripped = lines[index].strip
        if stripped.empty? || comment_line?(lines[index])
          index += 1
          next
        end

        nested_declaration = declaration_for_line(lines[index])
        if nested_declaration && %w[class module].include?(nested_declaration[:kind])
          index = ruby_block_finish_index(lines, index) + 1
          next
        end

        match = CONSTANT_ASSIGNMENT_PATTERN.match(lines[index])
        unless match
          index += 1
          next
        end

        finish_index = constant_assignment_finish_index(lines, index)
        entries << {
          name: match[2],
          text: lines[index..finish_index].join("\n").rstrip,
          range: (line_start_offsets[index]...(line_start_offsets[finish_index] + lines[finish_index].length))
        }
        index = finish_index + 1
      end
      entries
    end

    def split_ruby_array_elements(source)
      elements = []
      start_index = 0
      string_quote = nil
      escape = false
      source.each_char.with_index do |char, index|
        if string_quote
          if escape
            escape = false
          elsif char == "\\"
            escape = true
          elsif char == string_quote
            string_quote = nil
          end
          next
        end

        if char == "\"" || char == "'"
          string_quote = char
        elsif char == ","
          elements << source[start_index...index].strip
          start_index = index + 1
        end
      end
      elements << source[start_index..].to_s.strip
      elements.reject(&:empty?)
    end

    def normalize_array_element_key(element)
      element.to_s.strip
    end

    def multiline_array_elements(source)
      source.to_s.lines.filter_map do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        {
          indent: line[/\A\s*/],
          value: stripped.sub(/,\z/, "")
        }
      end
    end

    def append_multiline_array_elements(destination_body, appended, insertion_prefix)
      body_lines = destination_body.to_s.lines.map(&:chomp)
      element_indexes = body_lines.each_index.select do |index|
        stripped = body_lines[index].strip
        !stripped.empty? && !stripped.start_with?("#")
      end
      trailing_comma = element_indexes.empty? || body_lines[element_indexes.last].strip.end_with?(",")

      if trailing_comma
        insertion_lines = appended.map { |element| "#{insertion_prefix}#{element[:value]}," }
        return "#{destination_body.rstrip}\n#{insertion_lines.join("\n")}"
      end

      body_lines[element_indexes.last] = "#{body_lines[element_indexes.last]},"
      insertion_lines = appended.each_with_index.map do |element, index|
        suffix = index == appended.length - 1 ? "" : ","
        "#{insertion_prefix}#{element[:value]}#{suffix}"
      end
      "#{body_lines.join("\n").rstrip}\n#{insertion_lines.join("\n")}"
    end

    def constant_assignment_finish_index(lines, index)
      return hash_assignment_finish_line(lines, index) || index if lines[index].include?("{")
      return array_assignment_finish_line(lines, index) || index if lines[index].include?("[")

      index
    end

    def array_assignment_finish_line(lines, start_line)
      depth = 0
      in_string = nil
      escape = false
      start_line.upto(lines.length - 1) do |line_index|
        lines[line_index].each_char do |char|
          if in_string
            if escape
              escape = false
            elsif char == "\\"
              escape = true
            elsif char == in_string
              in_string = nil
            end
            next
          end

          if char == "\"" || char == "'"
            in_string = char
          elsif char == "["
            depth += 1
          elsif char == "]"
            depth -= 1
            return line_index if depth.zero?
          end
        end
      end
      nil
    end

    def visibility_section_start_index(index, consumed)
      return if consumed

      index
    end

    def direct_body_declaration_entries(text)
      lines = text.to_s.split("\n")
      return [] if lines.length < 3

      line_start_offsets = []
      offset = 0
      lines.each do |line|
        line_start_offsets << offset
        offset += line.length + 1
      end

      entries = []
      index = 1
      while index < lines.length - 1
        declaration = declaration_for_line(lines[index].strip)
        unless declaration && %w[class module].include?(declaration[:kind])
          index += 1
          next
        end

        finish_index = ruby_block_finish_index(lines, index)
        start_offset = line_start_offsets[index]
        finish_offset = line_start_offsets[finish_index] + lines[finish_index].length
        entries << {
          path: "/declarations/#{declaration[:name]}",
          name: declaration[:name],
          kind: declaration[:kind],
          merge_key: "#{declaration[:kind]}:#{declaration[:name]}",
          text: lines[index..finish_index].join("\n").rstrip,
          range: (start_offset...finish_offset)
        }
        index = finish_index + 1
      end
      entries
    end

    def declaration_closing_end_index(lines)
      depth = 0
      lines.each_with_index do |line, index|
        stripped = line.strip
        depth += 1 if declaration_for_line(stripped)
        depth -= 1 if stripped == "end"
        return index if depth.zero? && index.positive?
      end
      nil
    end

    def insert_declaration_body_blocks(destination_text, blocks, before_visibility: true, placement: :before_closing)
      lines = destination_text.to_s.split("\n")
      closing_index = declaration_closing_end_index(lines)
      return destination_text unless closing_index

      insertion_index = if placement == :after_opening
        1
      elsif before_visibility
        direct_visibility_section_index(lines, closing_index) || closing_index
      else
        closing_index
      end
      insertion = []
      insertion << "" unless insertion_index == 1 || lines[insertion_index - 1].to_s.strip.empty?
      insertion.concat(blocks.join("\n\n").split("\n"))
      insertion << "" if insertion_index != closing_index && !lines[insertion_index].to_s.strip.empty?
      lines.insert(insertion_index, *insertion)
      "#{lines.join("\n").sub(/\n+\z/, "")}\n".chomp
    end

    def direct_visibility_section_present?(text, visibility)
      lines = text.to_s.split("\n")
      closing_index = declaration_closing_end_index(lines)
      return false unless closing_index

      find_direct_visibility_section_index(lines, closing_index, visibility: visibility)
    end

    def direct_visibility_section_index(lines, closing_index)
      find_direct_visibility_section_index(lines, closing_index, visibility: nil)
    end

    def find_direct_visibility_section_index(lines, closing_index, visibility:)
      depth = 1
      1.upto(closing_index - 1) do |index|
        stripped = lines[index].strip
        visibility_match = visibility ? stripped == visibility : %w[private protected].include?(stripped)
        return index if depth == 1 && visibility_match

        depth += 1 if declaration_for_line(stripped)
        depth -= 1 if stripped == "end"
      end
      nil
    end

    def merge_ruby_hash_literals(template, destination)
      destination_by_key = destination.pairs.to_h { |pair| [pair.key, pair] }
      merged_pairs = template.pairs.map do |template_pair|
        destination_pair = destination_by_key[template_pair.key]
        if destination_pair.nil?
          template_pair
        elsif template_pair.value.is_a?(RubyHashNode) && destination_pair.value.is_a?(RubyHashNode)
          RubyHashPair.new(
            key: template_pair.key,
            value: merge_ruby_hash_literals(template_pair.value, destination_pair.value)
          )
        else
          destination_pair
        end
      end
      template_keys = template.pairs.map(&:key).to_h { |key| [key, true] }
      merged_pairs.concat(destination.pairs.reject { |pair| template_keys[pair.key] })
      RubyHashNode.new(pairs: merged_pairs, inline: template.inline)
    end

    def render_ruby_hash_literal(node, base_indent)
      return node.source unless node.is_a?(RubyHashNode)
      return render_inline_ruby_hash_literal(node) if node.inline

      child_indent = base_indent + 2
      lines = node.pairs.each_with_index.map do |pair, index|
        suffix = index == node.pairs.length - 1 ? "" : ","
        "#{" " * child_indent}#{pair.key}: #{render_ruby_hash_literal(pair.value, child_indent)}#{suffix}"
      end
      "{\n#{lines.join("\n")}\n#{" " * base_indent}}"
    end

    def render_inline_ruby_hash_literal(node)
      inner = node.pairs.map do |pair|
        "#{pair.key}: #{render_ruby_hash_literal(pair.value, 0)}"
      end.join(", ")
      "{#{inner}}"
    end

    def comment_line?(line)
      line.lstrip.start_with?("#")
    end

    def declaration_for_line(line)
      if (match = CLASS_PATTERN.match(line))
        { kind: "class", name: match[1] }
      elsif (match = MODULE_PATTERN.match(line))
        { kind: "module", name: match[1] }
      elsif (match = DEF_PATTERN.match(line))
        { kind: "def", name: match[2], signature: "#{match[1]}#{match[2]}" }
      end
    end

    def next_code_line_is_task?(lines, start_index)
      lines[start_index..].to_a.each do |line|
        next if line.strip.empty? || comment_line?(line)

        match = DSL_CALL_PATTERN.match(line)
        return match && match[:name] == "task"
      end
      false
    end

    def dsl_entry_finish_index(lines, start_index)
      return start_index unless lines[start_index].match?(/\bdo\b/)

      ruby_block_finish_index(lines, start_index)
    end

    def ruby_block_finish_index(lines, start_index)
      depth = 0
      cursor = start_index
      while cursor < lines.length
        stripped = lines[cursor].strip
        depth += stripped.scan(/\bdo\b/).length
        depth += 1 if declaration_for_line(stripped) || stripped.match?(/\A(begin|if|unless|case|while|until|for)\b/)
        depth -= 1 if stripped == "end"
        return cursor if depth <= 0 && cursor > start_index

        cursor += 1
      end
      lines.length - 1
    end

    def begin_block_signature(text)
      require_path = text[/^\s*require(?:_relative)?\s+["']([^"']+)["']/, 1]
      return "begin:require:#{require_path}" if require_path

      "begin:#{text.lines.first.to_s.strip}"
    end

    def dsl_entry_signature(name, line)
      case name
      when "source", "gemspec"
        name
      when "git_source", "gem", "eval_gemfile", "platform", "group", "task"
        first_argument = line[/\b#{Regexp.escape(name)}\s*(?:\(|\s)\s*["']([^"']+)["']/, 1] ||
          line[/\b#{Regexp.escape(name)}\s*(?:\(|\s)\s*:([a-zA-Z_]\w*[!?=]?)/, 1]
        first_argument ? "#{name}:#{normalize_dsl_argument(name, first_argument)}" : "#{name}:#{line.strip}"
      when "desc"
        "desc:#{line.strip}"
      end
    end

    def normalize_dsl_argument(name, argument)
      return argument.gsub(%r{/r\d+/}, "/") if name == "eval_gemfile"

      argument
    end

    def dsl_singleton_entry?(entry)
      %w[source gemspec].include?(entry[:name])
    end

    def normalize_rakefile_default_task_scaffold(content)
      lines = normalize_source(content).split("\n")
      desc_index = lines.find_index { |line| line.strip == RAKEFILE_DEFAULT_TASK_DESC }
      return content unless desc_index

      comment_index = preceding_code_line_index(lines, desc_index - 1)
      return content unless comment_index && lines[comment_index].strip == RAKEFILE_DEFAULT_TASK_COMMENT

      next_code_index = next_code_line_index(lines, desc_index + 1)
      return content if next_code_index && lines[next_code_index].match?(/\Atask\s+:default\b/)

      task_index = lines.each_index.find { |index| lines[index].match?(/\Atask\s+:default\b/) }
      return content unless task_index

      finish_index = dsl_entry_finish_index(lines, task_index)
      task_block = lines[task_index..finish_index]
      lines[task_index..finish_index] = []
      insertion_index = lines.find_index { |line| line.strip == RAKEFILE_DEFAULT_TASK_DESC } + 1
      insertion = task_block.dup
      insertion << "" unless lines[insertion_index].to_s.strip.empty?
      lines.insert(insertion_index, *insertion)
      "#{lines.join("\n").sub(/\n+\z/, "")}\n"
    end

    def preceding_code_line_index(lines, start_index)
      start_index.downto(0) do |index|
        next if lines[index].strip.empty?

        return index
      end
      nil
    end

    def next_code_line_index(lines, start_index)
      start_index.upto(lines.length - 1) do |index|
        next if lines[index].strip.empty?

        return index
      end
      nil
    end

    def surfaces_for_owner(owner_name:, comment_entries:)
      filtered_entries = comment_entries.filter { |entry| doc_comment_content?(entry[:raw]) }
      return [] if filtered_entries.empty?

      start_line = filtered_entries.first[:line]
      end_line = filtered_entries.last[:line]
      doc_surface = Ast::Merge.discovered_surface(
        surface_kind: "ruby_doc_comment",
        declared_language: "yard",
        effective_language: "yard",
        address: "document[0] > ruby_doc_comment[#{owner_name}]",
        parent_address: "document[0]",
        owner: Ast::Merge.surface_owner_ref(kind: "owned_region", address: "/declarations/#{owner_name}"),
        span: Ast::Merge.surface_span(start_line: start_line, end_line: end_line),
        reconstruction_strategy: "rewrite_with_prefix_preservation",
        metadata: {
          owner_signature: owner_name,
          comment_prefix: comment_prefix_for(filtered_entries.first[:raw]),
          entries: filtered_entries.map { |entry| { line: entry[:line], raw: entry[:raw] } }
        }
      )

      [doc_surface] + example_surfaces_for(doc_surface)
    end

    def example_surfaces_for(surface)
      entries = Array(surface.dig(:metadata, :entries))
      normalized = entries.map { |entry| normalize_comment_content(entry[:raw]) }

      normalized.each_with_index.filter_map do |content, tag_index|
        match = EXAMPLE_TAG.match(content)
        next unless match

        body_start = tag_index + 1
        body_end = next_tag_index(normalized, body_start) || normalized.length
        next if body_start >= body_end

        body_entries = entries[body_start...body_end]
        next if body_entries.nil? || body_entries.empty?

        declared_language = declared_example_language(match[:rest]) || "ruby"
        Ast::Merge.discovered_surface(
          surface_kind: "yard_example_block",
          declared_language: declared_language,
          effective_language: declared_language,
          address: "#{surface[:address]} > yard_example[#{tag_index}]",
          parent_address: surface[:address],
          owner: Ast::Merge.surface_owner_ref(kind: "owned_region", address: surface[:address]),
          span: Ast::Merge.surface_span(start_line: body_entries.first[:line], end_line: body_entries.last[:line]),
          reconstruction_strategy: "rewrite_with_prefix_preservation",
          metadata: {
            tag_kind: "example",
            tag_index: tag_index,
            tag_text: normalized[tag_index],
            comment_prefix: surface.dig(:metadata, :comment_prefix)
          }
        )
      end
    end

    def next_tag_index(normalized_lines, start_index)
      normalized_lines.each_with_index do |content, index|
        next if index < start_index
        return index if TAG_PREFIX.match?(content)
      end
      nil
    end

    def normalize_source(source)
      source.gsub(/\r\n?/, "\n")
    end

    def normalize_comment_content(raw)
      raw.to_s.sub(/\A\s*#\s?/, "").strip
    end

    def doc_comment_content?(raw)
      content = normalize_comment_content(raw)
      return false if content.empty?
      return false if DIRECTIVE_LINE.match?(content)
      return false if MAGIC_COMMENT_PREFIXES.any? { |prefix| content.start_with?("#{prefix}:") }

      true
    end

    def comment_prefix_for(raw)
      raw.to_s[/\A\s*#\s*/] || "# "
    end

    def declared_example_language(rest)
      match = rest.to_s.strip.match(/\A\[(?<language>[^\]]+)\]/)
      language = match && match[:language]
      return if language.nil? || language.empty?

      language.downcase.tr("-", "_")
    end

    module_function(
      :ruby_feature_profile,
      :available_ruby_backends,
      :ruby_backend_feature_profile,
      :ruby_plan_context,
      :parse_ruby,
      :match_ruby_owners,
      :ruby_method_move_detection,
      :merge_ruby,
      :ruby_discovered_surfaces,
      :ruby_delegated_child_operations,
      :apply_ruby_delegated_child_outputs,
      :merge_ruby_with_reviewed_nested_outputs,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope,
      :merge_ruby_with_nested_outputs,
      :analyze_ruby_document,
      :collect_ruby_require_entries,
      :collect_ruby_declaration_entries,
      :unsupported_feature_result
    )
  end
end
