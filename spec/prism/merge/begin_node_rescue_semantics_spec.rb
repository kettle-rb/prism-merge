# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodeRescueSemantics do
  def file_analysis(source)
    Prism::Merge::FileAnalysis.new(source)
  end

  def parse_first_statement(source)
    Prism.parse(source).value.statements.body.first
  end

  def first_rescue_clause(source)
    parse_first_statement(source).rescue_clause
  end

  def semantics_for(template_source, dest_source)
    described_class.new(
      template_analysis: file_analysis(template_source),
      dest_analysis: file_analysis(dest_source),
    )
  end

  describe "#normalized_clause_body_and_header_source" do
    it "switches header ownership to the side whose rescue binding the merged body needs" do
      template = <<~RUBY
        begin
          work
        rescue StandardError
          handle
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => e
          handle
          notify(e)
        end
      RUBY

      semantics = semantics_for(template, dest)

      result = semantics.normalized_clause_body_and_header_source(
        template_clause_node: first_rescue_clause(template),
        dest_clause_node: first_rescue_clause(dest),
        clause_body: "  handle\n  notify(e)\n",
        preferred_source: :template,
      )

      expect(result).to eq(
        header_source: :destination,
        clause_body: "  handle\n  notify(e)\n",
      )
    end

    it "rewrites preserved rescue-local references onto the emitted binding" do
      template = <<~RUBY
        begin
          work
        rescue StandardError => error
          template_only(error)
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => e
          destination_only(e)
        end
      RUBY

      semantics = semantics_for(template, dest)

      result = semantics.normalized_clause_body_and_header_source(
        template_clause_node: first_rescue_clause(template),
        dest_clause_node: first_rescue_clause(dest),
        clause_body: "  template_only(error)\n  destination_only(e)\n",
        preferred_source: :template,
      )

      expect(result).to eq(
        header_source: :template,
        clause_body: "  template_only(error)\n  destination_only(error)\n",
      )
    end

    it "keeps the template header when only the template rescue binding is referenced" do
      template = <<~RUBY
        begin
          work
        rescue StandardError => error
          template_only(error)
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => e
          destination_only(e)
        end
      RUBY

      semantics = semantics_for(template, dest)

      result = semantics.normalized_clause_body_and_header_source(
        template_clause_node: first_rescue_clause(template),
        dest_clause_node: first_rescue_clause(dest),
        clause_body: "  template_only(error)\n",
        preferred_source: :destination,
      )

      expect(result).to eq(
        header_source: :template,
        clause_body: "  template_only(error)\n",
      )
    end
  end

  describe "#merge_ordered_clause_types" do
    it "inserts missing clauses before the next shared clause when needed" do
      semantics = semantics_for("", "")
      specific_rescue = [:rescue_clause, ["RuntimeError"], 0]

      expect(semantics.merge_ordered_clause_types([:ensure_clause], [specific_rescue, :ensure_clause])).to eq([
        specific_rescue,
        :ensure_clause,
      ])
    end

    it "appends missing clauses when there are no shared neighbors" do
      semantics = semantics_for("", "")

      expect(semantics.merge_ordered_clause_types([], [:else_clause])).to eq([:else_clause])
    end
  end

  describe "#canonicalize_rescue_clause_order" do
    it "orders narrower built-in subclass rescues ahead of broader superclass rescues" do
      semantics = semantics_for("", "")
      clause_types = [
        [:rescue_clause, ["SystemCallError"], 0],
        [:rescue_clause, ["Errno::ENOENT"], 0],
      ]

      expect(semantics.canonicalize_rescue_clause_order(clause_types)).to eq([
        [:rescue_clause, ["Errno::ENOENT"], 0],
        [:rescue_clause, ["SystemCallError"], 0],
      ])
    end

    it "orders source-defined custom subclass rescues ahead of broader custom rescues" do
      source = <<~RUBY
        module QuxMergeSpec
          class BaseError < StandardError
          end

          class SpecificError < BaseError
          end
        end
      RUBY

      semantics = semantics_for(source, source)
      clause_types = [
        [:rescue_clause, ["QuxMergeSpec::BaseError"], 0],
        [:rescue_clause, ["QuxMergeSpec::SpecificError"], 0],
      ]

      expect(semantics.canonicalize_rescue_clause_order(clause_types)).to eq([
        [:rescue_clause, ["QuxMergeSpec::SpecificError"], 0],
        [:rescue_clause, ["QuxMergeSpec::BaseError"], 0],
      ])
    end
  end

  describe "#canonicalize_begin_clause_kind_order" do
    it "keeps rescue clauses ahead of ensure regardless of original order" do
      semantics = semantics_for("", "")
      clause_types = [
        :ensure_clause,
        [:rescue_clause, [:standard_error], 0],
      ]

      expect(semantics.canonicalize_begin_clause_kind_order(clause_types)).to eq([
        [:rescue_clause, [:standard_error], 0],
        :ensure_clause,
      ])
    end
  end

  describe "private helper coverage" do
    it "recognizes local variable reads and local reference matches" do
      semantics = semantics_for("", "")
      node = Prism.parse("error = 1\nerror\n").value.statements.body.last

      expect(semantics.send(:local_variable_read_names_in, node)).to eq(["error"])
      expect(semantics.send(:local_reference_node_named?, node, "error")).to be(true)
    end

    it "returns the fallback clause kind sort key for unknown clause kinds" do
      semantics = semantics_for("", "")

      expect(semantics.send(:clause_kind_sort_key, :custom_clause)).to eq(3)
    end

    it "tracks absolute source-defined exception superclasses" do
      source = <<~RUBY
        module QuxMergeSpec
          class BaseError < ::StandardError
          end

          class SpecificError < ::QuxMergeSpec::BaseError
          end
        end
      RUBY

      semantics = semantics_for(source, source)

      expect(semantics.send(:source_defined_exception_hierarchy)).to include(
        "QuxMergeSpec::BaseError" => "StandardError",
        "QuxMergeSpec::SpecificError" => "QuxMergeSpec::BaseError",
      )
    end

    it "returns false when exception constant coverage comparison raises" do
      semantics = semantics_for("", "")

      expect(semantics.send(:exception_constant_covers?, Object.new, RuntimeError)).to be(false)
    end

    it "resolves clause exception constants for known rescue clause types" do
      semantics = semantics_for("", "")

      expect(semantics.send(:rescue_clause_exception_constants, [:rescue_clause, ["StandardError"], 0])).to eq([StandardError])
    end

    it "returns nil when rescue reference lookup receives a non-rescue node" do
      semantics = semantics_for("", "")

      expect(semantics.send(:rescue_node_reference_name, parse_first_statement("value = 1\n"))).to be_nil
    end

    it "returns empty local-variable reads for blank or invalid source" do
      semantics = semantics_for("", "")

      expect(semantics.send(:local_variable_read_names_in_source, "   \n")).to eq([])
      expect(semantics.send(:local_variable_read_names_in_source, "def (")).to eq([])
    end

    it "returns false when local reference matching cannot run" do
      semantics = semantics_for("", "")

      expect(semantics.send(:local_reference_node_named?, nil, "error")).to be(false)
      expect(semantics.send(:local_reference_node_named?, parse_first_statement("value = 1\n"), nil)).to be(false)
    end

    it "returns existing offsets unchanged when no node is provided" do
      semantics = semantics_for("", "")

      expect(semantics.send(:local_reference_offsets_in, nil, "error", [[1, 2]])).to eq([[1, 2]])
    end

    it "leaves source unchanged when reference rewriting cannot proceed" do
      semantics = semantics_for("", "")

      expect(semantics.send(:rewrite_local_reference_in_source, "error\n", from: nil, to: "e")).to eq("error\n")
      expect(semantics.send(:rewrite_local_reference_in_source, "def (", from: "error", to: "e")).to eq("def (")
      expect(semantics.send(:rewrite_local_reference_in_source, "value = 1\n", from: "error", to: "e")).to eq("value = 1\n")
    end

    it "returns empty exception names for non-rescue clause types" do
      semantics = semantics_for("", "")

      expect(semantics.send(:rescue_clause_exception_names, :ensure_clause)).to eq([])
    end

    it "returns false when source-defined exception coverage inputs are invalid or unrelated" do
      semantics = semantics_for("", "")

      expect(semantics.send(:source_defined_exception_covers?, nil, "QuxMergeSpec::SpecificError")).to be(false)
      expect(semantics.send(:source_defined_exception_covers?, "QuxMergeSpec::BaseError", "OtherError")).to be(false)
    end

    it "returns false when rescue clause coverage inputs are not comparable" do
      semantics = semantics_for("", "")

      expect(semantics.send(:rescue_clause_covers?, :ensure_clause, [:rescue_clause, ["StandardError"], 0])).to be(false)
      expect(semantics.send(:rescue_clause_covers?, [:rescue_clause, [], 0], [:rescue_clause, ["StandardError"], 0])).to be(false)
      expect(semantics.send(:broader_rescue_clause_type_than?, :ensure_clause, [:rescue_clause, ["StandardError"], 0])).to be(false)
    end
  end
end
