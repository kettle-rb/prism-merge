# frozen_string_literal: true

module TreeHaver
  ParserRequest = Struct.new(:source, :language, :dialect, keyword_init: true) do
    def to_h
      {
        source: source,
        language: language,
        **(dialect ? { dialect: dialect } : {})
      }
    end
  end

  BackendReference = Struct.new(:id, :family, keyword_init: true) do
    def to_h
      { id: id, family: family }
    end
  end

  AdapterInfo = Struct.new(:backend, :backend_ref, :supports_dialects, :supported_policies, keyword_init: true) do
    def to_h
      {
        backend: backend,
        **(backend_ref ? { backend_ref: backend_ref.to_h } : {}),
        supports_dialects: supports_dialects,
        supported_policies: deep_dup(supported_policies || [])
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  FeatureProfile = Struct.new(:backend, :backend_ref, :supports_dialects, :supported_policies, keyword_init: true) do
    def to_h
      {
        backend: backend,
        **(backend_ref ? { backend_ref: backend_ref.to_h } : {}),
        supports_dialects: supports_dialects,
        supported_policies: deep_dup(supported_policies || [])
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ParserIdentity = Struct.new(:name, :version, :implementation, keyword_init: true) do
    def to_h
      {
        name: name,
        version: version,
        implementation: implementation
      }
    end
  end

  LanguageVersion = Struct.new(:version, :dialect, keyword_init: true) do
    def to_h
      {
        version: version,
        dialect: dialect
      }
    end
  end

  BackendCapability = Struct.new(
    :backend_ref,
    :language,
    :parser_identity,
    :language_version,
    :parse_error_behavior,
    :source_span_support,
    :source_fragment_support,
    :render_strategies,
    :semantic_role_support,
    :normalized_tree_support,
    :native_node_access,
    :diagnostics,
    keyword_init: true
  ) do
    def to_h
      {
        backend_ref: backend_ref.to_h,
        language: language,
        parser_identity: parser_identity.to_h,
        language_version: language_version.to_h,
        parse_error_behavior: parse_error_behavior,
        source_span_support: source_span_support,
        source_fragment_support: source_fragment_support,
        render_strategies: render_strategies,
        semantic_role_support: semantic_role_support,
        normalized_tree_support: normalized_tree_support,
        native_node_access: native_node_access,
        diagnostics: diagnostics
      }
    end
  end

  ParserDiagnostics = Struct.new(:backend, :backend_ref, :diagnostics, keyword_init: true) do
    def to_h
      {
        backend: backend,
        **(backend_ref ? { backend_ref: backend_ref.to_h } : {}),
        diagnostics: deep_dup(diagnostics || [])
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ProcessRequest = Struct.new(:source, :language, keyword_init: true) do
    def to_h
      {
        source: source,
        language: language
      }
    end
  end

  ProcessSpan = Struct.new(:start_byte, :end_byte, :start_row, :start_col, :end_row, :end_col, keyword_init: true) do
    def to_h
      {
        start_byte: start_byte,
        end_byte: end_byte,
        start_row: start_row,
        start_col: start_col,
        end_row: end_row,
        end_col: end_col
      }
    end
  end

  ByteRange = Struct.new(:start_byte, :end_byte, keyword_init: true) do
    def valid?
      start_byte.to_i >= 0 && end_byte.to_i >= start_byte.to_i
    end

    def length
      valid? ? end_byte.to_i - start_byte.to_i : 0
    end

    def contains_byte?(offset)
      valid? && offset.to_i >= start_byte.to_i && offset.to_i < end_byte.to_i
    end

    def contains_range?(other)
      valid? && other.valid? && other.start_byte.to_i >= start_byte.to_i && other.end_byte.to_i <= end_byte.to_i
    end

    def overlaps?(other)
      valid? && other.valid? && start_byte.to_i < other.end_byte.to_i && other.start_byte.to_i < end_byte.to_i
    end

    def to_h
      {
        start_byte: start_byte,
        end_byte: end_byte
      }
    end
  end

  SourcePoint = Struct.new(:row, :column, keyword_init: true) do
    def to_h
      {
        row: row,
        column: column
      }
    end
  end

  SourceSpan = Struct.new(:range, :start_point, :end_point, keyword_init: true) do
    def to_h
      {
        range: range.to_h,
        start_point: start_point.to_h,
        end_point: end_point.to_h
      }
    end
  end

  NODE_ROLES = %w[
    structural
    token
    trivia
    comment
    delimiter
    separator
    virtual
    error
    opaque
  ].freeze

  NormalizedTreeNode = Struct.new(
    :id,
    :kind,
    :role,
    :parent_id,
    :child_ids,
    :span,
    :field_name,
    :named,
    :anonymous,
    :has_source_text,
    :source_fragment,
    keyword_init: true
  ) do
    def to_h
      {
        id: id,
        kind: kind,
        role: role,
        parent_id: parent_id,
        child_ids: child_ids,
        span: span.to_h,
        field_name: field_name,
        named: named,
        anonymous: anonymous,
        has_source_text: has_source_text,
        source_fragment: source_fragment
      }
    end
  end

  def node_roles
    NODE_ROLES.dup
  end
  module_function :node_roles

  ByteEditSpan = Struct.new(:start_byte, :old_end_byte, :new_end_byte, :start_point, :old_end_point, :new_end_point, keyword_init: true) do
    def old_range
      ByteRange.new(start_byte: start_byte, end_byte: old_end_byte)
    end

    def new_range
      ByteRange.new(start_byte: start_byte, end_byte: new_end_byte)
    end

    def byte_delta
      new_end_byte.to_i - old_end_byte.to_i
    end

    def to_h
      {
        start_byte: start_byte,
        old_end_byte: old_end_byte,
        new_end_byte: new_end_byte,
        start_point: start_point.to_h,
        old_end_point: old_end_point.to_h,
        new_end_point: new_end_point.to_h
      }
    end
  end

  BinaryScalarValue = Struct.new(:kind, :value, :symbol, :raw_value, :encoding, :format, :description, keyword_init: true) do
    def to_h
      {
        kind: kind,
        **(value.nil? ? {} : { value: value }),
        **(symbol.nil? ? {} : { symbol: symbol }),
        **(raw_value.nil? ? {} : { raw_value: raw_value }),
        **(encoding.nil? ? {} : { encoding: encoding }),
        **(format.nil? ? {} : { format: format }),
        **(description.nil? ? {} : { description: description })
      }
    end
  end

  BinaryRenderPolicy = Struct.new(:schema_path, :byte_range, :operation, :disposition, :reason, keyword_init: true) do
    def to_h
      {
        schema_path: schema_path,
        **(byte_range ? { byte_range: byte_range.to_h } : {}),
        operation: operation,
        disposition: disposition,
        reason: reason
      }
    end
  end

  BinaryDiagnostic = Struct.new(:severity, :category, :message, :schema_path, :byte_range, keyword_init: true) do
    def to_h
      {
        severity: severity,
        category: category,
        message: message,
        schema_path: schema_path,
        **(byte_range ? { byte_range: byte_range.to_h } : {})
      }
    end
  end

  BinaryNestedDispatch = Struct.new(:schema_path, :family, :status, keyword_init: true) do
    def to_h
      {
        schema_path: schema_path,
        family: family,
        status: status
      }
    end
  end

  BinaryPayloadRegion = Struct.new(:kind, :schema_path, :byte_range, :expected_hex, keyword_init: true) do
    def to_h
      {
        kind: kind,
        schema_path: schema_path,
        byte_range: byte_range.to_h,
        expected_hex: expected_hex
      }
    end
  end

  BinaryRawPayload = Struct.new(:encoding, :value, :byte_length, :regions, keyword_init: true) do
    def to_h
      {
        encoding: encoding,
        value: value,
        byte_length: byte_length,
        regions: (regions || []).map(&:to_h)
      }
    end
  end

  BinaryMergeReport = Struct.new(:format, :schema, :matched_schema_paths, :preserved_ranges, :rewritten_nodes, :checksum_updates, :nested_dispatches, :diagnostics, keyword_init: true) do
    def to_h
      {
        format: format,
        schema: schema,
        matched_schema_paths: deep_dup(matched_schema_paths || []),
        preserved_ranges: (preserved_ranges || []).map(&:to_h),
        rewritten_nodes: deep_dup(rewritten_nodes || []),
        checksum_updates: deep_dup(checksum_updates || []),
        nested_dispatches: (nested_dispatches || []).map(&:to_h),
        diagnostics: (diagnostics || []).map(&:to_h)
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ZipArchiveInfo = Struct.new(:format, :schema, :entry_count, :central_directory_range, keyword_init: true) do
    def to_h
      {
        format: format,
        schema: schema,
        entry_count: entry_count,
        central_directory_range: central_directory_range.to_h
      }
    end
  end

  ZipArchiveEntry = Struct.new(:path, :normalized_path, :directory, :compression, :compressed_size, :uncompressed_size, :crc32, :local_header_range, :data_range, :central_directory_range, keyword_init: true) do
    def to_h
      {
        path: path,
        normalized_path: normalized_path,
        directory: directory,
        compression: compression,
        compressed_size: compressed_size,
        uncompressed_size: uncompressed_size,
        crc32: crc32,
        local_header_range: local_header_range.to_h,
        data_range: data_range.to_h,
        central_directory_range: central_directory_range.to_h
      }
    end
  end

  ZipMemberDecision = Struct.new(:normalized_path, :operation, :disposition, :nested_family, :reason, keyword_init: true) do
    def to_h
      {
        normalized_path: normalized_path,
        operation: operation,
        disposition: disposition,
        **(nested_family ? { nested_family: nested_family } : {}),
        reason: reason
      }
    end
  end

  ZipUnsafeEntry = Struct.new(:path, :normalized_path, :category, :reason, keyword_init: true) do
    def to_h
      {
        path: path,
        normalized_path: normalized_path,
        category: category,
        reason: reason
      }
    end
  end

  ZipFamilyReport = Struct.new(:archive, :entries, :member_decisions, :merge_report, :unsafe_entries, keyword_init: true) do
    def to_h
      {
        archive: archive.to_h,
        entries: (entries || []).map(&:to_h),
        member_decisions: (member_decisions || []).map(&:to_h),
        unsafe_entries: (unsafe_entries || []).map(&:to_h),
        merge_report: merge_report.to_h
      }
    end
  end

  def self.slice_byte_range(source, byte_range)
    source_bytesize = source.to_s.bytesize
    unless byte_range.valid? && byte_range.end_byte.to_i <= source_bytesize
      raise RangeError, "invalid byte range [#{byte_range.start_byte}, #{byte_range.end_byte}) for source length #{source_bytesize}"
    end

    source.to_s.byteslice(byte_range.start_byte.to_i...byte_range.end_byte.to_i)
  end

  def self.byte_offset_for_point(source, point)
    raise RangeError, "invalid source point (#{point.row}, #{point.column})" if point.row.to_i.negative? || point.column.to_i.negative?

    row = 0
    column = 0
    source.to_s.bytes.each_with_index do |byte, offset|
      return offset if row == point.row.to_i && column == point.column.to_i

      if byte == 10
        row += 1
        column = 0
      else
        column += 1
      end
    end
    return source.to_s.bytesize if row == point.row.to_i && column == point.column.to_i

    raise RangeError, "source point (#{point.row}, #{point.column}) is outside source"
  end

  ProcessStructureItem = Struct.new(:kind, :name, :span, keyword_init: true) do
    def to_h
      {
        kind: kind,
        **(name ? { name: name } : {}),
        span: span.to_h
      }
    end
  end

  ProcessImportInfo = Struct.new(:source, :items, :span, keyword_init: true) do
    def to_h
      {
        source: source,
        items: deep_dup(items || []),
        span: span.to_h
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ProcessDiagnostic = Struct.new(:message, :severity, keyword_init: true) do
    def to_h
      {
        message: message,
        severity: severity
      }
    end
  end

  LanguagePackAnalysis = Struct.new(:language, :dialect, :root_type, :has_error, :backend_ref, keyword_init: true) do
    def kind
      "tree-sitter"
    end

    def to_h
      {
        kind: kind,
        language: language,
        **(dialect ? { dialect: dialect } : {}),
        root_type: root_type,
        has_error: has_error,
        backend_ref: backend_ref.to_h
      }
    end
  end

  LanguagePackProcessAnalysis = Struct.new(:language, :structure, :imports, :diagnostics, :backend_ref, keyword_init: true) do
    def kind
      "tree-sitter-process"
    end

    def to_h
      {
        kind: kind,
        language: language,
        structure: (structure || []).map(&:to_h),
        imports: (imports || []).map(&:to_h),
        diagnostics: (diagnostics || []).map(&:to_h),
        backend_ref: backend_ref.to_h
      }
    end
  end

  KaitaiByteSpan = Struct.new(:start_byte, :end_byte, keyword_init: true) do
    def to_h
      {
        start_byte: start_byte,
        end_byte: end_byte
      }
    end
  end

  KaitaiTreeNode = Struct.new(:kind, :schema_path, :span, :fields, :children, keyword_init: true) do
    def to_h
      {
        kind: kind,
        schema_path: schema_path,
        span: span.to_h,
        fields: deep_dup(fields || {}),
        children: (children || []).map(&:to_h)
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  KaitaiTreeAnalysis = Struct.new(:schema, :root, :backend_ref, :source_byte_length, :diagnostics, keyword_init: true) do
    def kind
      "kaitai-tree"
    end

    def to_h
      {
        kind: kind,
        schema: schema,
        **(source_byte_length.nil? ? {} : { source_byte_length: source_byte_length }),
        root: root.to_h,
        backend_ref: backend_ref.to_h,
        diagnostics: (diagnostics || []).map(&:to_h)
      }
    end
  end
end
