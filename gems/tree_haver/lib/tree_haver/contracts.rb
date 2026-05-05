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

  KaitaiTreeAnalysis = Struct.new(:schema, :root, :backend_ref, keyword_init: true) do
    def kind
      "kaitai-tree"
    end

    def to_h
      {
        kind: kind,
        schema: schema,
        root: root.to_h,
        backend_ref: backend_ref.to_h
      }
    end
  end
end
