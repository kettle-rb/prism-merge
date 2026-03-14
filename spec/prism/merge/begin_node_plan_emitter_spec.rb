# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodePlanEmitter do
  def merger_for(template, dest, preference: :template, **options)
    merger = Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
    merger.instance_variable_set(:@result, merger.send(:build_result))
    merger
  end

  def first_begin_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def emit_result(template, dest, preference: :template, **options)
    merger = merger_for(template, dest, preference: preference, **options)
    template_node = first_begin_node(merger, :template)
    dest_node = first_begin_node(merger, :destination)

    described_class.new(merger: merger).emit(
      template_node: template_node,
      dest_node: dest_node,
      node_preference: preference,
      decision: Prism::Merge::MergeResult::DECISION_REPLACED,
      template_inline_by_line: merger.send(:wrapper_inline_comment_entries_by_line, merger.template_analysis, template_node),
      dest_inline_by_line: merger.send(:wrapper_inline_comment_entries_by_line, merger.dest_analysis, dest_node),
    )

    merger.result.to_s
  end

  describe "#emit" do
    it "emits a shared rescue clause using the destination header when the merged body needs its binding" do
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

      result = emit_result(template, dest)
      expected = [
        "rescue StandardError => e",
        "  handle",
        "  notify(e)",
      ].join("\n") + "\n"

      expect(result).to eq(expected)
    end

    it "emits shared clause bodies and copied unmatched tails for clause-only begin wrappers" do
      template = <<~RUBY
        begin
        rescue StandardError
          recover
        end
      RUBY

      dest = <<~RUBY
        begin
        rescue StandardError => e
          recover
          audit(e)
        ensure
          cleanup
        end
      RUBY

      result = emit_result(template, dest)
      expected = [
        "rescue StandardError => e",
        "  recover",
        "  audit(e)",
        "ensure",
        "  cleanup",
      ].join("\n") + "\n"

      expect(result).to eq(expected)
    end

    it "ignores unknown planner steps" do
      merger = merger_for("begin\nend\n", "begin\nend\n")
      emitter = described_class.new(merger: merger)
      unknown_step = Struct.new(:kind).new(:unknown)

      result = emitter.send(
        :emit_step,
        unknown_step,
        node_preference: :template,
        decision: Prism::Merge::MergeResult::DECISION_REPLACED,
        template_inline_by_line: Hash.new { |hash, key| hash[key] = [] },
        dest_inline_by_line: Hash.new { |hash, key| hash[key] = [] },
        begin_clause_line_map: {},
      )

      expect(result).to be_nil
      expect(merger.result.to_s).to eq("\n")
    end
  end
end
