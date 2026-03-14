# frozen_string_literal: true

RSpec.describe Prism::Merge::WrapperCommentSupport do
  def merger_for(template, dest, preference: :template, **options)
    Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
  end

  def first_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  describe "comment filtering and inline aggregation" do
    it "filters destination prefix comments and strips template magic comments when destination prefix lines were emitted" do
      template = <<~RUBY
        # frozen_string_literal: true

        def example
          :template
        end
      RUBY

      dest = <<~RUBY
        # frozen_string_literal: true

        # User docs
        def example
          :destination
        end
      RUBY

      merger = merger_for(template, dest)
      support = described_class.new(merger: merger)
      merger.instance_variable_set(:@dest_prefix_comment_lines, [1, 2])

      template_leading = support.filtered_leading_comments_for(first_node(merger, :template), :template)
      dest_leading = support.filtered_leading_comments_for(first_node(merger, :destination), :destination)

      expect(template_leading[:comments]).to be_empty
      expect(template_leading[:last_skipped_line]).to eq(1)
      expect(dest_leading[:comments].map { |comment| comment.slice.strip }).to eq(["# User docs"])
      expect(dest_leading[:last_skipped_line]).to eq(1)
    end

    it "collects wrapper inline comment entries from owner and boundary lines without duplicates" do
      source = <<~RUBY
        begin # keep begin note
          work
        rescue StandardError => error # keep rescue note
          handle(error)
        end # keep end note
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      begin_node = first_node(merger, :template)
      entries_by_line = support.wrapper_inline_comment_entries_by_line(merger.template_analysis, begin_node)

      expect(entries_by_line.keys).to include(1, 3, 5)
      expect(entries_by_line[1].map { |entry| entry[:raw] }).to eq(["# keep begin note"])
      expect(entries_by_line[3].map { |entry| entry[:raw] }).to eq(["# keep rescue note"])
      expect(entries_by_line[5].map { |entry| entry[:raw] }).to eq(["# keep end note"])
    end
  end

  describe "comment emission" do
    it "emits blank lines and external trailing comments while preserving provenance" do
      source = <<~RUBY
        def example
          :body
        end

        # trailing note
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      node = first_node(merger, :template)
      result = merger.send(:build_result)
      trailing_comments = support.external_trailing_comments_for(node)

      emitted_line = support.emit_external_trailing_comments(
        result,
        trailing_comments,
        source_node: node,
        analysis: merger.template_analysis,
        source: :template,
        decision: Prism::Merge::MergeResult::DECISION_REPLACED,
      )

      expect(emitted_line).to eq(5)
      expect(result.to_s).to eq("\n# trailing note\n")
      expect(result.line_metadata.map { |meta| meta[:template_line] }).to eq([4, 5])
    end

    it "appends inline comment entries onto existing source text" do
      merger = merger_for("x = 1\n", "x = 1\n")
      support = described_class.new(merger: merger)

      expect(
        support.append_inline_comment_entries("rescue StandardError", [{raw: "# keep this explanation"}]),
      ).to eq("rescue StandardError # keep this explanation")
    end
  end
end
