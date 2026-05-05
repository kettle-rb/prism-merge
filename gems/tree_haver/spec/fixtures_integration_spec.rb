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
      schema: "png.ksy",
      root: node,
      backend_ref: described_class::KAITAI_STRUCT_BACKEND
    )

    expect(analysis.kind).to eq("kaitai-tree")
    expect(json_ready(analysis.root.to_h)).to eq(json_ready(node_fixture))
  end

  it "conforms to the slice-722 portable byte location contract fixture" do
    fixture = diagnostics_fixture("portable_byte_location_contract")
    byte_range = described_class::ByteRange.new(**fixture[:byte_range])
    point = described_class::SourcePoint.new(**fixture[:source_point])
    overlapping_range = described_class::ByteRange.new(**fixture.dig(:comparison_ranges, :overlapping))
    disjoint_range = described_class::ByteRange.new(**fixture.dig(:comparison_ranges, :disjoint))

    expect(byte_range.length).to eq(fixture.dig(:expected, :length))
    expect(described_class.slice_byte_range(fixture[:source], byte_range)).to eq(fixture.dig(:expected, :slice))
    expect(byte_range.contains_byte?(byte_range.start_byte)).to eq(fixture.dig(:expected, :contains_start))
    expect(byte_range.contains_byte?(byte_range.end_byte)).to eq(fixture.dig(:expected, :contains_end))
    expect(byte_range.overlaps?(overlapping_range)).to eq(fixture.dig(:expected, :overlaps))
    expect(byte_range.overlaps?(disjoint_range)).to eq(fixture.dig(:expected, :disjoint))
    expect(described_class.byte_offset_for_point(fixture[:source], point)).to eq(fixture.dig(:expected, :line_column_offset))
  end

  it "conforms to the slice-723 binary core contract fixture" do
    fixture = diagnostics_fixture("binary_core_contract")
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
