# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodeClauseBodyMerger do
  def merger_for(template, dest, preference: :template, **options)
    Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
  end

  def first_begin_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def clause_region_for(merger, node, type)
    merger.send(:begin_node_clause_regions, node).find { |region| region[:type] == type }
  end

  def merge_clause_body(template, dest, preference: :template, **options)
    merger = merger_for(template, dest, preference: preference, **options)
    begin_node_template = first_begin_node(merger, :template)
    begin_node_dest = first_begin_node(merger, :destination)
    rescue_type = [:rescue_clause, [:standard_error], 0]

    described_class.new(merger: merger).merge(
      template_clause_node: begin_node_template.rescue_clause,
      template_clause_region: clause_region_for(merger, begin_node_template, rescue_type),
      dest_clause_node: begin_node_dest.rescue_clause,
      dest_clause_region: clause_region_for(merger, begin_node_dest, rescue_type),
    )
  end

  describe "#merge" do
    it "returns a value object with merged body text and both trailing suffixes" do
      template = <<~RUBY
        begin
          work
        rescue StandardError
          handle
          # template suffix
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError
          handle
          notify
          # destination suffix
        end
      RUBY

      result = merge_clause_body(template, dest)

      expect(result).to be_a(described_class::MergeResult)
      expect(result.merged_body).to eq("  handle\n  notify")
      expect(result[:template_trailing_suffix]).to eq("  # template suffix\n")
      expect(result[:dest_trailing_suffix]).to eq("  # destination suffix\n")
    end

    it "returns nil when the clause bodies share no mergeable statements" do
      template = <<~RUBY
        begin
          work
        rescue StandardError
          alpha_call
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError
          beta_call
        end
      RUBY

      expect(merge_clause_body(template, dest)).to be_nil
    end

    it "forwards recursive merge options so template preference and template-only additions still apply" do
      template = <<~RUBY
        begin
          work
        rescue StandardError
          class Inner
            def shared
              :template
            end

            def added
              :template_only
            end
          end
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError
          class Inner
            def shared
              :destination
            end

            def custom
              :destination_only
            end
          end
        end
      RUBY

      result = merge_clause_body(template, dest, add_template_only_nodes: true)

      expect(result.merged_body).to include(":template")
      expect(result.merged_body).to include("def added")
      expect(result.merged_body).to include("def custom")
    end
  end
end
