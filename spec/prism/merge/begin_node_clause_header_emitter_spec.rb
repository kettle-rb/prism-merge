# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodeClauseHeaderEmitter do
  def merger_for(template, dest, preference: :template, **options)
    merger = Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
    merger.instance_variable_set(:@result, merger.send(:build_result))
    merger
  end

  def first_begin_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def clause_region_for(merger, node, type)
    merger.send(:begin_node_clause_regions, node).find { |region| region[:type] == type }
  end

  def emit_header(template, dest, header_source: :template, preference: :template, **options)
    merger = merger_for(template, dest, preference: preference, **options)
    template_begin = first_begin_node(merger, :template)
    dest_begin = first_begin_node(merger, :destination)
    clause_type = [:rescue_clause, ["RuntimeError", "StandardError"], 0]
    template_clause = template_begin.rescue_clause
    dest_clause = dest_begin.rescue_clause

    described_class.new(merger: merger).emit(
      template_clause_node: template_clause,
      template_region: clause_region_for(merger, template_begin, clause_type),
      dest_clause_node: dest_clause,
      dest_region: clause_region_for(merger, dest_begin, clause_type),
      header_source: header_source,
      decision: Prism::Merge::MergeResult::DECISION_REPLACED,
      template_inline_by_line: merger.send(:wrapper_inline_comment_entries_by_line, merger.template_analysis, template_begin),
      dest_inline_by_line: merger.send(:wrapper_inline_comment_entries_by_line, merger.dest_analysis, dest_begin),
    )

    merger.result.to_s
  end

  describe "#emit" do
    it "emits multi-line rescue headers through the computed header end line" do
      template = <<~RUBY
        begin
          work
        rescue RuntimeError,
               StandardError
          handle
        end
      RUBY

      dest = template

      result = emit_header(template, dest)
      expected = [
        "rescue RuntimeError,",
        "       StandardError",
      ].join("\n") + "\n"

      expect(result).to eq(expected)
    end

    it "falls back to the destination inline comment when the template header has none" do
      template = <<~RUBY
        begin
          work
        rescue RuntimeError, StandardError
          handle
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue RuntimeError, StandardError # keep this explanation
          handle
        end
      RUBY

      result = emit_header(template, dest)

      expect(result).to eq("rescue RuntimeError, StandardError # keep this explanation\n")
    end

    it "keeps the template inline comment when one is already present" do
      template = <<~RUBY
        begin
          work
        rescue RuntimeError, StandardError # keep template comment
          handle
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue RuntimeError, StandardError # destination note
          handle
        end
      RUBY

      result = emit_header(template, dest)

      expect(result).to eq("rescue RuntimeError, StandardError # keep template comment\n")
    end
  end
 end
