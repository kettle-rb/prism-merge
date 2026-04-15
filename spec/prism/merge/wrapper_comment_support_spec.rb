# frozen_string_literal: true

RSpec.describe Prism::Merge::WrapperCommentSupport do
  def merger_for(template, dest, preference: :template, **options)
    Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
  end

  def first_node(merger, side)
    analysis = (side == :template) ? merger.template_analysis : merger.dest_analysis
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

    it "reads orphan regions from a cached native augmenter for the retained owner set" do
      source = <<~RUBY
        def first_method
          :first
        end

        # gap comment for removed owner
        def second_method
          :second
        end

        def third_method
          :third
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      first_owner = merger.dest_analysis.statements[0]
      third_owner = merger.dest_analysis.statements[2]
      merger.instance_variable_set(
        :@dest_comment_augmenter,
        merger.dest_analysis.comment_augmenter(owners: [first_owner, third_owner]),
      )

      expect(
        support.orphan_regions_for(first_owner, source: :destination, analysis: merger.dest_analysis).map(&:normalized_content),
      ).to eq(["gap comment for removed owner"])
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

    it "preserves the original separator before inline comments" do
      merger = merger_for("x = 1\n", "x = 1\n")
      support = described_class.new(merger: merger)

      expect(
        support.append_inline_comment_entries(
          'spec.add_dependency("version_gem", "~> 1.1")',
          [{raw: "# ruby >= 2.2.0", separator: "              "}],
        ),
      ).to eq('spec.add_dependency("version_gem", "~> 1.1")              # ruby >= 2.2.0')
    end

    it "preserves trailing spaces already owned by the base line before replaying the donor separator" do
      merger = merger_for("x = 1\n", "x = 1\n")
      support = described_class.new(merger: merger)

      expect(
        support.append_inline_comment_entries(
          'VERSION = "2.0.0"  ',
          [{raw: "# keep this explanation", separator: "  "}],
        ),
      ).to eq('VERSION = "2.0.0"    # keep this explanation')
    end

    it "emits orphan comment regions with intervening blank lines and destination provenance" do
      source = <<~RUBY
        def first_method
          :first
        end

        # gap comment for removed owner
        def second_method
          :second
        end

        def third_method
          :third
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      first_owner = merger.dest_analysis.statements[0]
      third_owner = merger.dest_analysis.statements[2]
      augmenter = merger.dest_analysis.comment_augmenter(owners: [first_owner, third_owner])

      emitted_line = support.emit_orphan_regions(
        result,
        augmenter.attachment_for(first_owner).orphan_regions,
        analysis: merger.dest_analysis,
        source: :destination,
        decision: Prism::Merge::MergeResult::DECISION_KEPT_DEST,
        previous_line: first_owner.location.end_line,
      )

      expect(emitted_line).to eq(5)
      expect(result.to_s).to eq("\n# gap comment for removed owner\n")
      expect(result.line_metadata.map { |meta| meta[:dest_line] }).to eq([4, 5])
    end

    it "emits orphan comment regions with template provenance" do
      source = <<~RUBY
        def first_method
          :first
        end

        # gap comment for removed owner
        def second_method
          :second
        end

        def third_method
          :third
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      first_owner = merger.template_analysis.statements[0]
      third_owner = merger.template_analysis.statements[2]
      augmenter = merger.template_analysis.comment_augmenter(owners: [first_owner, third_owner])

      emitted_line = support.emit_orphan_regions(
        result,
        augmenter.attachment_for(first_owner).orphan_regions,
        analysis: merger.template_analysis,
        source: :template,
        decision: Prism::Merge::MergeResult::DECISION_KEPT_TEMPLATE,
        previous_line: first_owner.location.end_line,
      )

      expect(emitted_line).to eq(5)
      expect(result.line_metadata.map { |meta| meta[:template_line] }).to eq([4, 5])
    end

    it "handles empty base text and multiple inline entries" do
      merger = merger_for("x = 1\n", "x = 1\n")
      support = described_class.new(merger: merger)

      expect(
        support.append_inline_comment_entries("", [{raw: "# first"}, {raw: "# second"}]),
      ).to eq("# first # second")
    end

    it "extracts comment node lines and text across supported helper lookup modes" do
      merger = merger_for("x = 1\n", "x = 1\n")
      support = described_class.new(merger: merger)
      location_only = Object.new
      location_only.define_singleton_method(:location) { Struct.new(:start_line).new(12) }
      text_only = Object.new
      text_only.define_singleton_method(:text) { "# from text   " }

      expect(support.send(:comment_node_line, location_only)).to eq(12)
      expect(support.send(:comment_node_line, Object.new)).to be_nil
      expect(support.send(:comment_node_text, Struct.new(:slice).new("# from slice   "))).to eq("# from slice   ")
      expect(support.send(:comment_node_text, text_only)).to eq("# from text   ")
      expect(support.send(:comment_node_text, 123)).to eq("123")
    end
  end
end
