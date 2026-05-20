# frozen_string_literal: true

require "json"
require "tree_sitter_language_pack"

module TreeHaver
  TSLP_BACKEND = BackendReference.new(
    id: "tslp",
    family: "tree-sitter"
  ).freeze
  KREUZBERG_LANGUAGE_PACK_BACKEND = BackendReference.new(
    id: "kreuzberg-language-pack",
    family: "tree-sitter"
  ).freeze

  BackendRegistry.register(TSLP_BACKEND)
  BackendRegistry.register(KREUZBERG_LANGUAGE_PACK_BACKEND)
  BackendRegistry.register_availability_checker(:tslp) do
    defined?(TreeSitterLanguagePack) && TreeSitterLanguagePack.respond_to?(:process)
  end
  BackendRegistry.register_availability_checker(:"kreuzberg-language-pack") do
    BackendRegistry.available?(:tslp)
  end

  module_function

  def language_pack_adapter_info
    AdapterInfo.new(
      backend: TSLP_BACKEND.id,
      backend_ref: TSLP_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def language_pack_feature_profile
    FeatureProfile.new(
      backend: TSLP_BACKEND.id,
      backend_ref: TSLP_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def parse_with_language_pack(request)
    ensure_language_pack_language(request.language)
    raw = language_pack_result_hash(TreeSitterLanguagePack.process(
      request.source,
      JSON.generate(language: request.language, diagnostics: true)
    ))
    return fallback_parse_with_language_pack(request) unless raw

    diagnostics = Array(raw["diagnostics"])
    return parse_error_result(request.language) unless diagnostics.empty?

    analysis = LanguagePackAnalysis.new(
      language: request.language,
      dialect: request.dialect,
      root_type: inferred_root_type(request),
      has_error: false,
      backend_ref: TSLP_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  rescue StandardError => e
    parse_result(
      ok: false,
      diagnostics: [diagnostic("error", "unsupported_feature", e.message)]
    )
  end

  def process_with_language_pack(request)
    ensure_language_pack_language(request.language)
    raw = language_pack_result_hash(TreeSitterLanguagePack.process(
      request.source,
      JSON.generate(language: request.language, structure: true, imports: true, diagnostics: true)
    ))
    return fallback_process_with_language_pack(request) unless raw

    analysis = LanguagePackProcessAnalysis.new(
      language: raw.fetch("language"),
      structure: Array(raw["structure"]).map do |item|
        ProcessStructureItem.new(
          kind: item.fetch("kind").downcase,
          name: item["name"],
          span: process_span(item.fetch("span"))
        )
      end,
      imports: normalize_imports(request.language, Array(raw["imports"])),
      diagnostics: Array(raw["diagnostics"]).map do |item|
        ProcessDiagnostic.new(
          message: item.fetch("message"),
          severity: item.fetch("severity")
        )
      end,
      backend_ref: TSLP_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  rescue StandardError => e
    parse_result(
      ok: false,
      diagnostics: [diagnostic("error", "unsupported_feature", e.message)]
    )
  end

  def ensure_language_pack_language(language)
    return if TreeSitterLanguagePack.has_language(language)

    TreeSitterLanguagePack.init(JSON.generate(languages: [language]))
  end
  private_class_method :ensure_language_pack_language

  def language_pack_result_hash(raw)
    return raw if raw.is_a?(Hash)
    return raw.to_h if raw.respond_to?(:to_h)
    if raw.respond_to?(:language)
      return {
        "language" => raw.language,
        "structure" => Array(raw.structure).map { |item| language_pack_object_hash(item) },
        "imports" => Array(raw.imports).map { |item| language_pack_object_hash(item) },
        "diagnostics" => Array(raw.diagnostics).map { |item| language_pack_object_hash(item) },
      }
    end

    parsed = JSON.parse(raw.to_json)
    parsed.is_a?(Hash) ? parsed : nil
  rescue StandardError
    nil
  end
  private_class_method :language_pack_result_hash

  def language_pack_object_hash(object)
    return object if object.is_a?(Hash)

    object.methods(false).each_with_object({}) do |method_name, result|
      result[method_name.to_s] = object.public_send(method_name)
    rescue StandardError
      next
    end
  end
  private_class_method :language_pack_object_hash

  def fallback_parse_with_language_pack(request)
    return parse_error_result(request.language) unless fallback_source_valid?(request.language, request.source)

    analysis = LanguagePackAnalysis.new(
      language: request.language,
      dialect: request.dialect,
      root_type: inferred_root_type(request),
      has_error: false,
      backend_ref: TSLP_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  end
  private_class_method :fallback_parse_with_language_pack

  def fallback_process_with_language_pack(request)
    analysis = LanguagePackProcessAnalysis.new(
      language: request.language,
      structure: fallback_structure_items(request.language, request.source),
      imports: fallback_import_items(request.language, request.source),
      diagnostics: [],
      backend_ref: TSLP_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  end
  private_class_method :fallback_process_with_language_pack

  def fallback_source_valid?(language, source)
    return ruby_source_valid?(source) if language == "ruby"

    true
  end
  private_class_method :fallback_source_valid?

  def ruby_source_valid?(source)
    RubyVM::InstructionSequence.compile(source)
    true
  rescue SyntaxError
    false
  end
  private_class_method :ruby_source_valid?

  def fallback_structure_items(language, source)
    lines = source.lines
    lines.each.with_index.filter_map do |line, index|
      kind, name = fallback_structure_match(language, line)
      next unless kind

      ProcessStructureItem.new(
        kind: kind,
        name: name,
        span: fallback_structure_span(source, lines, index, language)
      )
    end
  end
  private_class_method :fallback_structure_items

  def fallback_structure_span(source, lines, line_index, language)
    return fallback_ruby_block_span(source, lines, line_index) if language == "ruby"
    return fallback_brace_block_span(source, lines, line_index) if %w[go rust typescript javascript].include?(language)

    fallback_line_span(source, line_index, lines.fetch(line_index))
  end
  private_class_method :fallback_structure_span

  def fallback_brace_block_span(source, lines, line_index)
    return fallback_line_span(source, line_index, lines.fetch(line_index)) unless lines.fetch(line_index).include?("{")

    depth = 0
    seen_open = false
    end_index = line_index
    lines[line_index..].each_with_index do |line, offset|
      depth += line.count("{")
      seen_open ||= line.include?("{")
      depth -= line.count("}")
      end_index = line_index + offset
      break if seen_open && depth <= 0
    end
    fallback_span_for_lines(source, line_index, end_index)
  end
  private_class_method :fallback_brace_block_span

  def fallback_ruby_block_span(source, lines, line_index)
    depth = 0
    end_index = line_index
    lines[line_index..].each_with_index do |line, offset|
      stripped = line.strip
      depth += 1 if stripped.match?(/\A(class|module|def|if|unless|case|begin|do)\b/)
      depth -= 1 if stripped == "end"
      end_index = line_index + offset
      break if offset.positive? && depth <= 0
    end
    fallback_span_for_lines(source, line_index, end_index)
  end
  private_class_method :fallback_ruby_block_span

  def fallback_structure_match(language, line)
    case language
    when "typescript", "javascript"
      return ["function", Regexp.last_match(1)] if line =~ /\bfunction\s+([A-Za-z_$][\w$]*)/
      return ["class", Regexp.last_match(1)] if line =~ /\bclass\s+([A-Za-z_$][\w$]*)/
      return ["interface", Regexp.last_match(1)] if line =~ /\binterface\s+([A-Za-z_$][\w$]*)/
    when "go"
      return ["function", Regexp.last_match(1)] if line =~ /\bfunc\s+([A-Za-z_]\w*)\s*\(/
      return ["struct", Regexp.last_match(1)] if line =~ /\btype\s+([A-Za-z_]\w*)\s+struct\b/
    when "rust"
      return ["function", Regexp.last_match(1)] if line =~ /\bfn\s+([A-Za-z_]\w*)\s*\(/
      return ["struct", Regexp.last_match(1)] if line =~ /\bstruct\s+([A-Za-z_]\w*)\b/
    when "ruby"
      return ["class", Regexp.last_match(1)] if line =~ /^\s*class\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)/
      return ["method", Regexp.last_match(1)] if line =~ /^\s*def\s+([A-Za-z_]\w*[!?=]?)/
    end

    nil
  end
  private_class_method :fallback_structure_match

  def fallback_import_items(language, source)
    source.each_line.with_index.filter_map do |line, index|
      source_name, items = fallback_import_match(language, line)
      next unless source_name

      ProcessImportInfo.new(
        source: source_name,
        items: items,
        span: fallback_line_span(source, index, line)
      )
    end
  end
  private_class_method :fallback_import_items

  def fallback_import_match(language, line)
    case language
    when "typescript", "javascript"
      return [Regexp.last_match(2), Regexp.last_match(1).split(",").map(&:strip)] if line =~ /^\s*import\s+\{\s*([^}]+)\s*\}\s+from\s+["']([^"']+)["']/
      return [Regexp.last_match(2), Regexp.last_match(1).split(",").map(&:strip)] if line =~ /^\s*import\s+type\s+\{\s*([^}]+)\s*\}\s+from\s+["']([^"']+)["']/
      return [Regexp.last_match(1), []] if line =~ /^\s*import\s+["']([^"']+)["']/
    when "go", "rust"
      return [Regexp.last_match(1), []] if line =~ /^\s*(?:import|use)\s+["']?([^"';]+)["']?/
    end

    nil
  end
  private_class_method :fallback_import_match

  def fallback_line_span(source, line_index, line)
    start_byte = source.lines.take(line_index).join.bytesize
    ProcessSpan.new(
      start_byte: start_byte,
      end_byte: start_byte + line.bytesize,
      start_row: line_index,
      start_col: 0,
      end_row: line_index,
      end_col: line.chomp.length
    )
  end
  private_class_method :fallback_line_span

  def fallback_span_for_lines(source, start_index, end_index)
    lines = source.lines
    start_byte = lines.take(start_index).join.bytesize
    end_byte = lines.take(end_index + 1).join.bytesize
    ProcessSpan.new(
      start_byte: start_byte,
      end_byte: end_byte,
      start_row: start_index,
      start_col: 0,
      end_row: end_index,
      end_col: lines.fetch(end_index, "").chomp.length
    )
  end
  private_class_method :fallback_span_for_lines

  def parse_error_result(language)
    parse_result(
      ok: false,
      diagnostics: [
        diagnostic(
          "error",
          "parse_error",
          "tree-sitter-language-pack reported syntax errors for #{language}."
        )
      ]
    )
  end
  private_class_method :parse_error_result

  def process_span(raw)
    ProcessSpan.new(
      start_byte: raw.fetch("start_byte"),
      end_byte: raw.fetch("end_byte"),
      start_row: raw["start_row"] || raw.fetch("start_line"),
      start_col: raw["start_col"] || raw.fetch("start_column"),
      end_row: raw["end_row"] || raw.fetch("end_line"),
      end_col: raw["end_col"] || raw.fetch("end_column")
    )
  end
  private_class_method :process_span

  def inferred_root_type(request)
    stripped = request.source.lstrip
    case request.language
    when "json"
      return "object" if stripped.start_with?("{")
      return "array" if stripped.start_with?("[")

      "scalar"
    else
      request.language
    end
  end
  private_class_method :inferred_root_type

  def normalize_imports(language, raw_imports)
    raw_imports.map do |item|
      source, items =
        if language == "typescript"
          normalize_typescript_import(item)
        else
          [item["module"] || item["source"] || "", Array(item["names"] || item["items"])]
        end

      ProcessImportInfo.new(
        source: source,
        items: items,
        span: process_span(item.fetch("span"))
      )
    end
  end
  private_class_method :normalize_imports

  def normalize_typescript_import(item)
    raw_source = item["module"] || item["source"] || ""
    source_match = raw_source.match(/from\s+['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]/)
    source = source_match&.captures&.compact&.first || raw_source.strip
    names = if (named_items = raw_source.match(/\{([^}]+)\}/))
      named_items[1]
        .split(",")
        .map { |part| part.gsub(/\btype\b/, "").strip }
        .reject(&:empty?)
    else
      Array(item["names"] || item["items"])
    end

    [source, names]
  end
  private_class_method :normalize_typescript_import

  def parse_result(ok:, diagnostics:, analysis: nil, policies: [])
    {
      ok: ok,
      diagnostics: diagnostics,
      **(analysis ? { analysis: analysis } : {}),
      policies: policies
    }
  end
  private_class_method :parse_result

  def diagnostic(severity, category, message)
    {
      severity: severity,
      category: category,
      message: message
    }
  end
  private_class_method :diagnostic
end
