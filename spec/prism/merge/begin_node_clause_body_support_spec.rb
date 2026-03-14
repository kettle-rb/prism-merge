# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodeClauseBodySupport do
  def merger_for(template, dest, **options)
    Prism::Merge::SmartMerger.new(template, dest, **options)
  end

  def support_for(template, dest, **options)
    merger = merger_for(template, dest, **options)
    [merger, merger.send(:begin_node_clause_body_support)]
  end

  def first_begin_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def clause_region_for(merger, node, type)
    merger.send(:begin_node_clause_regions, node).find { |region| region[:type] == type }
  end

  describe "#clause_statements_node" do
    it "returns nil for non-clause nodes" do
      merger, support = support_for("begin\n  work\nend\n", "begin\n  work\nend\n")

      expect(support.clause_statements_node(first_begin_node(merger, :template))).to be_nil
    end
  end

  describe "header and body slicing" do
    it "computes rescue header boundaries and preserves trailing clause suffix lines" do
      source = <<~RUBY
        begin
          work
        rescue IOError, SystemCallError => error
          handle(error)
          # trailing note
        end
      RUBY

      merger, support = support_for(source, source)
      begin_node = first_begin_node(merger, :template)
      rescue_node = begin_node.rescue_clause
      rescue_region = clause_region_for(merger, begin_node, [:rescue_clause, ["IOError", "SystemCallError"], 0])

      expect(support.clause_header_end_line(rescue_node, rescue_region)).to eq(3)
      expect(support.clause_body_start_line(rescue_node, rescue_region)).to eq(4)
      expect(
        support.extract_region_body(rescue_region, merger.template_analysis, body_start_line: 4, body_end_line: 4),
      ).to eq("  handle(error)\n")
      expect(support.clause_body_components(rescue_node, rescue_region, merger.template_analysis)).to eq(
        merge_body: "  handle(error)\n",
        trailing_suffix: "  # trailing note\n",
      )
    end

    it "returns empty components when a clause has no statements node" do
      source = <<~RUBY
        begin
          work
        ensure
          # keep cleanup note
        end
      RUBY

      merger, support = support_for(source, source)
      begin_node = first_begin_node(merger, :template)
      ensure_node = begin_node.ensure_clause
      ensure_region = clause_region_for(merger, begin_node, :ensure_clause)

      expect(support.clause_body_components(ensure_node, ensure_region, merger.template_analysis)).to eq(
        merge_body: "",
        trailing_suffix: "",
      )
    end
  end

  describe "text helpers" do
    it "splits leading comment prefixes and detects freeze markers" do
      _, support = support_for("begin\nend\n", "begin\nend\n", freeze_token: "kettle-dev")
      body_text = "  # leading note\n\n  # kettle-dev:freeze\n  work\n"

      expect(support.split_leading_comment_prefix(body_text)).to eq([
        "  # leading note\n\n  # kettle-dev:freeze\n",
        "  work\n",
      ])
      expect(support.body_contains_freeze_markers?(body_text)).to be(true)
      expect(support.body_contains_freeze_markers?("  # leading note\n  work\n")).to be(false)
    end
  end

  describe "statement signature helpers" do
    it "collects signatures from begin bodies and clause bodies" do
      source = <<~RUBY
        begin
          work
        rescue StandardError => error
          handle(error)
        ensure
          cleanup
        end
      RUBY

      merger, support = support_for(source, source)
      begin_node = first_begin_node(merger, :template)
      signatures = support.begin_node_statement_signatures(begin_node, merger.template_analysis)
      work_signature = merger.template_analysis.generate_signature(begin_node.statements.body.first)
      rescue_signature = merger.template_analysis.generate_signature(begin_node.rescue_clause.statements.body.first)
      ensure_signature = merger.template_analysis.generate_signature(begin_node.ensure_clause.statements.body.first)

      expect(signatures).to include(work_signature, rescue_signature, ensure_signature)
    end

    it "detects duplicated clause bodies already represented in the preferred begin" do
      template = <<~RUBY
        begin
          work
        rescue StandardError
          cleanup
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => error
          handle(error)
        ensure
          cleanup
        end
      RUBY

      merger, support = support_for(template, dest, preference: :template)
      dest_begin = first_begin_node(merger, :destination)
      template_begin = first_begin_node(merger, :template)

      expect(
        support.clause_body_fully_duplicated_in_preferred_begin?(
          dest_begin.ensure_clause,
          merger.dest_analysis,
          template_begin,
          merger.template_analysis,
        ),
      ).to be(true)
    end

    it "returns false when clause statements do not produce usable signatures" do
      template = <<~RUBY
        begin
          work
        rescue StandardError
          "literal only"
        end
      RUBY

      signature_generator = lambda do |node|
        if node.is_a?(Prism::StringNode)
          nil
        else
          node
        end
      end

      merger, support = support_for(template, template, signature_generator: signature_generator)
      begin_node = first_begin_node(merger, :template)

      expect(
        support.clause_body_fully_duplicated_in_preferred_begin?(
          begin_node.rescue_clause,
          merger.template_analysis,
          begin_node,
          merger.template_analysis,
        ),
      ).to be(false)
    end

    it "checks whether clause bodies share at least one mergeable statement signature" do
      _, support = support_for("begin\nend\n", "begin\nend\n")

      expect(support.clause_bodies_have_matching_statements?("  shared_call\n", "  shared_call\n  custom_call\n")).to be(true)
      expect(support.clause_bodies_have_matching_statements?("", "  shared_call\n")).to be(false)
      expect(support.clause_bodies_have_matching_statements?("  alpha_call\n", "  beta_call\n")).to be(false)
    end
  end
end
