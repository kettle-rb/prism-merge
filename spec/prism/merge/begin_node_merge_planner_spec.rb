# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodeMergePlanner do
  def merger_for(template, dest, preference: :template, **options)
    merger = Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
    merger.merge
    merger
  end

  def first_begin_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def planner_for(template, dest, preference: :template, **options)
    merger = merger_for(template, dest, preference: preference, **options)
    described_class.new(
      merger: merger,
      template_node: first_begin_node(merger, :template),
      dest_node: first_begin_node(merger, :destination),
      node_preference: preference,
    )
  end

  describe "#plan" do
    it "plans a shared merged rescue clause using the header source required by the merged binding" do
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

      plan = planner_for(template, dest).plan

      expect(plan.map(&:kind)).to eq([:merged_shared_clause])
      expect(plan.first.header_source).to eq(:destination)
      expect(plan.first.body_text).to eq("  handle\n  notify(e)")
    end

    it "plans a copied unmatched ensure clause when only one side has it" do
      template = <<~RUBY
        begin
          work
        rescue StandardError => e
          handle(e)
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => e
          handle(e)
        ensure
          cleanup
        end
      RUBY

      plan = planner_for(template, dest, preference: :template).plan

      expect(plan.map(&:kind)).to eq([:merged_shared_clause, :copied_unmatched_clause])
      ensure_step = plan.last
      expect(ensure_step.clause_type).to eq(:ensure_clause)
      expect(ensure_step.copied_analysis_side).to eq(:destination)
    end

    it "skips an unmatched non-preferred clause whose body migrated elsewhere in the preferred BeginNode" do
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
        rescue StandardError => e
          handle(e)
        ensure
          cleanup
        end
      RUBY

      plan = planner_for(template, dest, preference: :template).plan

      expect(plan.map(&:kind)).to eq([:fallback_shared_clause])
      expect(plan.map(&:clause_type)).to eq([[:rescue_clause, [:standard_error], 0]])
      expect(plan.first.body_text).to eq("  cleanup\n")
    end

    it "skips an unmatched template clause whose body already migrated into the preferred destination BeginNode" do
      template = <<~RUBY
        begin
          work
        rescue StandardError => error
          cleanup(error)
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => error
          handle(error)
        ensure
          cleanup(error)
        end
      RUBY

      plan = planner_for(template, dest, preference: :destination).plan

      expect(plan.map(&:kind)).to eq([:fallback_shared_clause, :copied_unmatched_clause])
      expect(plan.map(&:clause_type)).to eq([[:rescue_clause, [:standard_error], 0], :ensure_clause])
    end
  end
end
