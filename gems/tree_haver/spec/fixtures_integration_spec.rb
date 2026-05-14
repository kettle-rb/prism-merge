# frozen_string_literal: true

require "pathname"

RSpec.describe TreeHaver do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
  end

  def diagnostics_fixture(role)
    path = Ast::Merge.conformance_fixture_path(manifest, "diagnostics", role)
    raise "missing diagnostics fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the slice-06 parser request fixture" do
    fixture = diagnostics_fixture("parser_request")

    request = described_class::ParserRequest.new(**fixture[:request])
    expect(json_ready(request.to_h)).to eq(json_ready(fixture[:request]))

    adapter_info = described_class::AdapterInfo.new(
      backend: fixture.dig(:adapter_info, :backend),
      supports_dialects: fixture.dig(:adapter_info, :supports_dialects),
      supported_policies: []
    )
    expect(json_ready(adapter_info.to_h.slice(:backend, :supports_dialects))).to eq(json_ready(fixture[:adapter_info]))
  end

  it "conforms to the slice-19 adapter policy support fixture" do
    fixture = diagnostics_fixture("adapter_policy_support")
    adapter_info = described_class::AdapterInfo.new(
      backend: fixture.dig(:adapter_info, :backend),
      supports_dialects: fixture.dig(:adapter_info, :supports_dialects),
      supported_policies: fixture.dig(:adapter_info, :supported_policies)
    )
    expect(json_ready(adapter_info.to_h.slice(:backend, :supports_dialects, :supported_policies))).to eq(json_ready(fixture[:adapter_info]))
  end

  it "conforms to the slice-20 adapter feature profile fixture" do
    fixture = diagnostics_fixture("adapter_feature_profile")
    profile = described_class::FeatureProfile.new(
      backend: fixture.dig(:feature_profile, :backend),
      supports_dialects: fixture.dig(:feature_profile, :supports_dialects),
      supported_policies: fixture.dig(:feature_profile, :supported_policies)
    )
    expect(json_ready(profile.to_h.slice(:backend, :supports_dialects, :supported_policies))).to eq(json_ready(fixture[:feature_profile]))
  end

  it "conforms to the slice-25 backend registry fixture" do
    fixture = diagnostics_fixture("backend_registry")
    backends = [
      described_class::BackendReference.new(id: "native", family: "builtin"),
      described_class::BackendReference.new(id: "tree-sitter", family: "tree-sitter")
    ]
    expect(json_ready(backends.map(&:to_h))).to eq(json_ready(fixture[:backends]))

    profile = described_class::FeatureProfile.new(
      backend: "tree-sitter",
      backend_ref: backends[1],
      supports_dialects: true,
      supported_policies: []
    )
    expect(json_ready(profile.to_h[:backend_ref])).to eq(json_ready(fixture[:backends][1]))
  end

  it "exposes PEG backend references for parser-plurality slices" do
    expect(json_ready(described_class::CITRUS_BACKEND.to_h)).to eq(
      json_ready({ id: "citrus", family: "peg" })
    )
    expect(json_ready(described_class::PARSLET_BACKEND.to_h)).to eq(
      json_ready({ id: "parslet", family: "peg" })
    )

    expect(json_ready(described_class.peg_adapter_info(described_class::CITRUS_BACKEND).to_h[:backend_ref])).to eq(
      json_ready({ id: "citrus", family: "peg" })
    )
    expect(json_ready(described_class.peg_feature_profile(described_class::PARSLET_BACKEND).to_h[:backend_ref])).to eq(
      json_ready({ id: "parslet", family: "peg" })
    )
  end

  it "conforms to the slice-721 Kaitai tree-haver substrate fixture" do
    fixture = diagnostics_fixture("kaitai_tree_haver_substrate")

    expect(json_ready(described_class::KAITAI_STRUCT_BACKEND.to_h)).to eq(json_ready(fixture[:backend]))
    expect(json_ready(described_class.kaitai_adapter_info.to_h)).to eq(json_ready(fixture[:adapter_info]))
    expect(json_ready(described_class.kaitai_feature_profile.to_h)).to eq(json_ready(fixture[:feature_profile]))

    node_fixture = fixture[:tree_node]
    analysis_fixture = fixture[:analysis]
    child_fixture = node_fixture[:children].first
    node = described_class::KaitaiTreeNode.new(
      kind: node_fixture[:kind],
      schema_path: node_fixture[:schema_path],
      span: described_class::KaitaiByteSpan.new(**node_fixture[:span]),
      fields: node_fixture[:fields],
      children: [
        described_class::KaitaiTreeNode.new(
          kind: child_fixture[:kind],
          schema_path: child_fixture[:schema_path],
          span: described_class::KaitaiByteSpan.new(**child_fixture[:span]),
          fields: child_fixture[:fields],
          children: []
        )
      ]
    )
    analysis = described_class::KaitaiTreeAnalysis.new(
      schema: analysis_fixture[:schema],
      root: node,
      backend_ref: described_class::KAITAI_STRUCT_BACKEND,
      source_byte_length: analysis_fixture[:source_byte_length],
      diagnostics: analysis_fixture[:diagnostics].map do |diagnostic|
        described_class::BinaryDiagnostic.new(
          severity: diagnostic[:severity],
          category: diagnostic[:category],
          message: diagnostic[:message],
          schema_path: diagnostic[:schema_path],
          byte_range: described_class::ByteRange.new(**diagnostic[:byte_range])
        )
      end
    )

    expect(analysis.kind).to eq("kaitai-tree")
    expect(analysis.source_byte_length).to eq(analysis_fixture[:source_byte_length])
    expect(analysis.diagnostics.first.schema_path).to eq(analysis_fixture.dig(:diagnostics, 0, :schema_path))
    expect(json_ready(analysis.root.to_h)).to eq(json_ready(node_fixture))
  end

  it "conforms to the slice-722 portable byte location contract fixture" do
    fixture = diagnostics_fixture("portable_byte_location_contract")
    byte_range = described_class::ByteRange.new(**fixture[:byte_range])
    point = described_class::SourcePoint.new(**fixture[:source_point])
    edit_fixture = fixture[:edit_span]
    edit_span = described_class::ByteEditSpan.new(
      start_byte: edit_fixture[:start_byte],
      old_end_byte: edit_fixture[:old_end_byte],
      new_end_byte: edit_fixture[:new_end_byte],
      start_point: described_class::SourcePoint.new(**edit_fixture[:start_point]),
      old_end_point: described_class::SourcePoint.new(**edit_fixture[:old_end_point]),
      new_end_point: described_class::SourcePoint.new(**edit_fixture[:new_end_point])
    )
    overlapping_range = described_class::ByteRange.new(**fixture.dig(:comparison_ranges, :overlapping))
    disjoint_range = described_class::ByteRange.new(**fixture.dig(:comparison_ranges, :disjoint))

    expect(byte_range.length).to eq(fixture.dig(:expected, :length))
    expect(described_class.slice_byte_range(fixture[:source], byte_range)).to eq(fixture.dig(:expected, :slice))
    expect(byte_range.contains_byte?(byte_range.start_byte)).to eq(fixture.dig(:expected, :contains_start))
    expect(byte_range.contains_byte?(byte_range.end_byte)).to eq(fixture.dig(:expected, :contains_end))
    expect(byte_range.overlaps?(overlapping_range)).to eq(fixture.dig(:expected, :overlaps))
    expect(byte_range.overlaps?(disjoint_range)).to eq(fixture.dig(:expected, :disjoint))
    expect(described_class.byte_offset_for_point(fixture[:source], point)).to eq(fixture.dig(:expected, :line_column_offset))
    expect(edit_span.old_range.length).to eq(fixture.dig(:expected, :old_edit_length))
    expect(edit_span.new_range.length).to eq(fixture.dig(:expected, :new_edit_length))
    expect(edit_span.byte_delta).to eq(fixture.dig(:expected, :edit_delta))
    expect(described_class.slice_byte_range(fixture[:source], edit_span.old_range)).to eq(fixture.dig(:expected, :old_edit_slice))
  end

  it "conforms to the slice-782 normalized tree node fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-782-normalized-tree-node", "normalized-tree-node.json"))

    expect(described_class.node_roles).to eq(fixture[:node_roles])
    node = normalized_tree_node(fixture[:node])
    child = normalized_tree_node(fixture[:child])

    expect(node.role).to eq("structural")
    expect(node.child_ids.fetch(1)).to eq(child.id)
    expect(child.parent_id).to eq(node.id)
    expect(child.field_name).to eq("declaration")
    expect(child.has_source_text).to be(true)
  end

  it "conforms to the slice-783 backend capability report fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-783-backend-capability-report", "backend-capability-report.json"))
    capability_fixture = fixture[:capability]
    capability = described_class::BackendCapability.new(
      backend_ref: described_class::BackendReference.new(**capability_fixture[:backend_ref]),
      language: capability_fixture[:language],
      parser_identity: described_class::ParserIdentity.new(**capability_fixture[:parser_identity]),
      language_version: described_class::LanguageVersion.new(**capability_fixture[:language_version]),
      parse_error_behavior: capability_fixture[:parse_error_behavior],
      source_span_support: capability_fixture[:source_span_support],
      source_fragment_support: capability_fixture[:source_fragment_support],
      render_strategies: capability_fixture[:render_strategies],
      semantic_role_support: capability_fixture[:semantic_role_support],
      normalized_tree_support: capability_fixture[:normalized_tree_support],
      native_node_access: capability_fixture[:native_node_access],
      diagnostics: capability_fixture[:diagnostics]
    )

    expect(capability.backend_ref.id).to eq("go-dst")
    expect(capability.backend_ref.family).to eq("native")
    expect(capability.language).to eq("go")
    expect(capability.parser_identity.name).to eq("github.com/dave/dst")
    expect(capability.parse_error_behavior).to eq("diagnostic_and_partial_tree")
    expect(capability.render_strategies.first).to eq("source_fragment_reuse")
    expect(capability.normalized_tree_support).to be(true)
    expect(capability.native_node_access).to be(true)
  end

  it "conforms to the slice-784 source fragment extraction fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-784-source-fragment-extraction", "source-fragment-extraction.json"))
    fragment = described_class.extract_source_fragment(
      fixture[:source],
      source_span(fixture[:span]),
      fixture[:strategy]
    )

    expect(fragment.text).to eq(fixture.dig(:fragment, :text))
    expect(fragment.available).to eq(fixture.dig(:fragment, :available))
    expect(fragment.strategy).to eq(fixture.dig(:fragment, :strategy))
    expect(fragment.byte_length).to eq(fixture.dig(:fragment, :byte_length))
    expect(fragment.diagnostics.length).to eq(fixture.dig(:fragment, :diagnostics).length)
  end

  it "conforms to the slice-723 binary core contract fixture" do
    fixture = diagnostics_fixture("binary_core_contract")
    payload_fixture = fixture[:raw_payload]
    payload = described_class::BinaryRawPayload.new(
      encoding: payload_fixture[:encoding],
      value: payload_fixture[:value],
      byte_length: payload_fixture[:byte_length],
      regions: payload_fixture[:regions].map do |region|
        described_class::BinaryPayloadRegion.new(
          kind: region[:kind],
          schema_path: region[:schema_path],
          byte_range: described_class::ByteRange.new(**region[:byte_range]),
          expected_hex: region[:expected_hex]
        )
      end
    )
    scalar_values = fixture[:scalar_values].map do |item|
      described_class::BinaryScalarValue.new(**item)
    end
    render_policies = fixture[:render_policies].map do |item|
      described_class::BinaryRenderPolicy.new(
        schema_path: item[:schema_path],
        byte_range: described_class::ByteRange.new(**item[:byte_range]),
        operation: item[:operation],
        disposition: item[:disposition],
        reason: item[:reason]
      )
    end
    report_fixture = fixture[:merge_report]
    report = described_class::BinaryMergeReport.new(
      format: report_fixture[:format],
      schema: report_fixture[:schema],
      matched_schema_paths: report_fixture[:matched_schema_paths],
      preserved_ranges: report_fixture[:preserved_ranges].map { |range| described_class::ByteRange.new(**range) },
      rewritten_nodes: report_fixture[:rewritten_nodes],
      checksum_updates: report_fixture[:checksum_updates],
      nested_dispatches: report_fixture[:nested_dispatches].map { |dispatch| described_class::BinaryNestedDispatch.new(**dispatch) },
      diagnostics: report_fixture[:diagnostics].map do |diagnostic|
        described_class::BinaryDiagnostic.new(
          severity: diagnostic[:severity],
          category: diagnostic[:category],
          message: diagnostic[:message],
          schema_path: diagnostic[:schema_path],
          byte_range: diagnostic[:byte_range] && described_class::ByteRange.new(**diagnostic[:byte_range])
        )
      end
    )

    payload_bytes = [payload.value].pack("H*")
    expect(payload.encoding).to eq("hex")
    expect(payload_bytes.bytesize).to eq(payload.byte_length)
    expect(payload.regions.map(&:kind)).to eq(%w[header length body checksum])
    expect(payload.regions.first.byte_range.length).to eq(8)
    expect(payload_bytes.byteslice(payload.regions.last.byte_range.start_byte...payload.regions.last.byte_range.end_byte).unpack1("H*")).to eq(payload.regions.last.expected_hex)
    expect(scalar_values.length).to eq(9)
    expect(scalar_values.first.kind).to eq("string")
    expect(scalar_values.last.kind).to eq("null")
    expect(render_policies[0].operation).to eq("preserve")
    expect(render_policies[1].disposition).to eq("requires_renderer")
    expect(render_policies[2].disposition).to eq("unsafe")
    expect(report.format).to eq("png")
    expect(report.preserved_ranges.first.length).to eq(25)
    expect(report.nested_dispatches.first.family).to eq("text")
    expect(report.diagnostics.first.category).to eq("unsupported_checksum_rewrite")
  end

  def normalized_tree_node(fixture)
    described_class::NormalizedTreeNode.new(
      id: fixture[:id],
      kind: fixture[:kind],
      role: fixture[:role],
      parent_id: fixture[:parent_id],
      child_ids: fixture[:child_ids],
      span: source_span(fixture[:span]),
      field_name: fixture[:field_name],
      named: fixture[:named],
      anonymous: fixture[:anonymous],
      has_source_text: fixture[:has_source_text],
      source_fragment: fixture[:source_fragment]
    )
  end

  def source_span(fixture)
    described_class::SourceSpan.new(
      range: described_class::ByteRange.new(**fixture[:range]),
      start_point: described_class::SourcePoint.new(**fixture[:start_point]),
      end_point: described_class::SourcePoint.new(**fixture[:end_point])
    )
  end

  it "conforms to the slice-724 and slice-729 ZIP family fixtures" do
    fixture = diagnostics_fixture("zip_family_contract")
    report_fixture = fixture[:merge_report]
    report = described_class::ZipFamilyReport.new(
      archive: described_class::ZipArchiveInfo.new(
        format: fixture.dig(:archive, :format),
        schema: fixture.dig(:archive, :schema),
        entry_count: fixture.dig(:archive, :entry_count),
        central_directory_range: described_class::ByteRange.new(**fixture.dig(:archive, :central_directory_range))
      ),
      entries: fixture[:entries].map do |entry|
        described_class::ZipArchiveEntry.new(
          path: entry[:path],
          normalized_path: entry[:normalized_path],
          directory: entry[:directory],
          compression: entry[:compression],
          compressed_size: entry[:compressed_size],
          uncompressed_size: entry[:uncompressed_size],
          crc32: entry[:crc32],
          local_header_range: described_class::ByteRange.new(**entry[:local_header_range]),
          data_range: described_class::ByteRange.new(**entry[:data_range]),
          central_directory_range: described_class::ByteRange.new(**entry[:central_directory_range])
        )
      end,
      member_decisions: fixture[:member_decisions].map { |decision| described_class::ZipMemberDecision.new(**decision) },
      unsafe_entries: fixture[:unsafe_entries].map { |entry| described_class::ZipUnsafeEntry.new(**entry) },
      merge_report: described_class::BinaryMergeReport.new(
        format: report_fixture[:format],
        schema: report_fixture[:schema],
        matched_schema_paths: report_fixture[:matched_schema_paths],
        preserved_ranges: report_fixture[:preserved_ranges].map { |range| described_class::ByteRange.new(**range) },
        rewritten_nodes: report_fixture[:rewritten_nodes],
        checksum_updates: report_fixture[:checksum_updates],
        nested_dispatches: report_fixture[:nested_dispatches].map { |dispatch| described_class::BinaryNestedDispatch.new(**dispatch) },
        diagnostics: report_fixture[:diagnostics].map { |diagnostic| described_class::BinaryDiagnostic.new(**diagnostic) }
      )
    )

    expect(report.archive.entry_count).to eq(report.entries.length)
    expect(report.member_decisions[1].nested_family).to eq("xml")
    expect(report.unsafe_entries.map(&:category)).to include("path_traversal", "duplicate_normalized_path", "encrypted_member")
    expect(report.merge_report.preserved_ranges.first.length).to eq(76)
  end

  it "conforms to the slice-100 process baseline fixture" do
    fixture = diagnostics_fixture("process_baseline")
    result = described_class.process_with_language_pack(
      described_class::ProcessRequest.new(**fixture[:request])
    )

    expect(result[:ok]).to be(true)
    analysis = result[:analysis]
    expect(analysis.language).to eq(fixture.dig(:expected, :language))
    expect(
      json_ready(
        analysis.structure.map do |item|
          {
            kind: item.kind,
            **(item.name ? { name: item.name } : {})
          }
        end
      )
    ).to eq(json_ready(fixture.dig(:expected, :structure)))
    expect(
      json_ready(
        analysis.imports.map do |item|
          {
            source: item.source,
            items: item.items
          }
        end
      )
    ).to eq(json_ready(fixture.dig(:expected, :imports)))
  end

  it "supports temporary backend context selection" do
    expect(described_class.current_backend_id).to be_nil

    described_class.with_backend("citrus") do
      expect(described_class.current_backend_id).to eq("citrus")

      described_class.with_backend("parslet") do
        expect(described_class.current_backend_id).to eq("parslet")
      end

      expect(described_class.current_backend_id).to eq("citrus")
    end

    expect(described_class.current_backend_id).to be_nil
  end

  it "provides PEG framework parsing helpers" do
    require "toml"
    require "toml-rb"

    citrus = described_class.parse_with_citrus("title = \"x\"\n", grammar_module: TomlRB::Document)
    expect(citrus[:ok]).to be(true)
    expect(json_ready(citrus[:backend_ref].to_h)).to eq(json_ready({ id: "citrus", family: "peg" }))

    parslet = described_class.parse_with_parslet("title = \"x\"\n", grammar_class: TOML::Parslet)
    expect(parslet[:ok]).to be(true)
    expect(json_ready(parslet[:backend_ref].to_h)).to eq(json_ready({ id: "parslet", family: "peg" }))
  end
end
