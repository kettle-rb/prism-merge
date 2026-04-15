# frozen_string_literal: true

RSpec.describe Prism::Merge::NodeEmissionSupport do
  def merger_for(template, dest, preference: :template, **options)
    Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
  end

  def first_node(merger, side)
    analysis = (side == :template) ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def second_node(merger, side)
    analysis = (side == :template) ? merger.template_analysis : merger.dest_analysis
    analysis.statements[1]
  end

  describe "#emit_dest_prefix_lines" do
    it "emits shebang, destination magic comment, and separating blank line before the first node" do
      source = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        # docs
        class Example
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emitted_line = support.emit_dest_prefix_lines(result: result, analysis: merger.dest_analysis)

      expect(emitted_line).to eq(3)
      expect(result.to_s).to eq("#!/usr/bin/env ruby\n# frozen_string_literal: true\n\n")
      expect(merger.instance_variable_get(:@dest_prefix_comment_lines)).to eq(Set[1, 2, 3])
    end
  end

  describe "#emit_dest_gap_lines" do
    it "emits only blank lines between destination nodes using the shared leading gap" do
      source = <<~RUBY
        class A
        end


        class B
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      last_output_line = support.emit_dest_gap_lines(
        result: result,
        analysis: merger.dest_analysis,
        last_output_line: 2,
        next_node: second_node(merger, :destination),
      )

      expect(last_output_line).to eq(4)
      expect(result.to_s).to eq("\n\n")
      expect(result.line_metadata.map { |meta| meta[:dest_line] }).to eq([3, 4])
    end

    it "falls back to scanning blank lines when leading comments interrupt node adjacency" do
      source = <<~RUBY
        class A
        end

        # docs for B
        class B
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      last_output_line = support.emit_dest_gap_lines(
        result: result,
        analysis: merger.dest_analysis,
        last_output_line: 2,
        next_node: second_node(merger, :destination),
      )

      expect(last_output_line).to eq(3)
      expect(result.to_s).to eq("\n")
      expect(result.line_metadata.map { |meta| meta[:dest_line] }).to eq([3])
    end
  end

  describe "#emit_matched_template_node" do
    it "falls back to destination leading, inline, and external trailing comments while keeping template code" do
      template = <<~RUBY
        def example
          :template
        end
      RUBY

      dest = <<~RUBY
        # User docs
        def example
          :destination
        end # keep end note

        # trailing note
      RUBY

      merger = merger_for(template, dest, preference: :template)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emission = support.emit_matched_template_node(
        result: result,
        template_node: first_node(merger, :template),
        dest_node: first_node(merger, :destination),
      )

      expect(emission).to eq({
        last_emitted_dest_line: 6,
        preserve_trailing_blank_line_progress: true,
      })
      expect(result.to_s).to eq(<<~RUBY)
        # User docs
        def example
          :template
        end # keep end note

        # trailing note
      RUBY
      expect(result.line_metadata.map { |meta| [meta[:template_line], meta[:dest_line]] }).to eq([
        [nil, 1],
        [1, nil],
        [2, nil],
        [3, nil],
        [nil, 5],
        [nil, 6],
      ])
    end

    it "does not duplicate template leading comments already emitted by an adjacent destination-only sibling" do
      template = <<~RUBY
        # Why is gem "cgi" here?
        #   compatibility workaround
        eval_gemfile "modular/x_std_libs.gemfile"
      RUBY

      dest = <<~RUBY
        # Why is gem "cgi" here?
        #   compatibility workaround
        eval_gemfile "modular/rspec.gemfile"
        eval_gemfile "modular/x_std_libs.gemfile"
      RUBY

      merger = merger_for(template, dest, preference: :template, add_template_only_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emission = support.emit_matched_template_node(
        result: result,
        template_node: first_node(merger, :template),
        dest_node: second_node(merger, :destination),
      )

      expect(emission).to eq({last_emitted_dest_line: nil})
      expect(result.to_s).to eq(<<~RUBY)
        eval_gemfile "modular/x_std_libs.gemfile"
      RUBY
    end

    it "falls back to destination orphan regions when a removed destination-only sibling owned the gap comments" do
      template = <<~RUBY
        def first_method
          :template
        end

        def third_method
          :template
        end
      RUBY

      dest = <<~RUBY
        def first_method
          :destination
        end

        # docs for removed second_method
        def second_method
          :destination_only
        end

        def third_method
          :destination
        end
      RUBY

      merger = merger_for(template, dest, preference: :template, remove_template_missing_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      template_first = first_node(merger, :template)
      dest_first = first_node(merger, :destination)
      merger.instance_variable_set(
        :@template_comment_augmenter,
        merger.template_analysis.comment_augmenter(owners: merger.template_analysis.statements),
      )
      merger.instance_variable_set(
        :@dest_comment_augmenter,
        merger.dest_analysis.comment_augmenter(owners: [dest_first, merger.dest_analysis.statements[2]]),
      )

      emission = support.emit_matched_template_node(
        result: result,
        template_node: template_first,
        dest_node: dest_first,
      )

      expect(emission).to eq({last_emitted_dest_line: 5})
      expect(result.to_s).to eq(<<~RUBY)
        def first_method
          :template
        end

        # docs for removed second_method
      RUBY
      expect(result.line_metadata.map { |meta| [meta[:template_line], meta[:dest_line]] }).to eq([
        [1, nil],
        [2, nil],
        [3, nil],
        [nil, 4],
        [nil, 5],
      ])
    end

    it "emits destination orphan regions after destination trailing comments when both are preserved" do
      template = <<~RUBY
        def first_method
          :template
        end

        def third_method
          :template
        end
      RUBY

      dest = <<~RUBY
        def first_method
          :destination
        end

        # trailing note

        # docs for removed second_method
        def second_method
          :destination_only
        end

        def third_method
          :destination
        end
      RUBY

      merger = merger_for(template, dest, preference: :template, remove_template_missing_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      template_first = first_node(merger, :template)
      dest_first = first_node(merger, :destination)
      merger.instance_variable_set(
        :@template_comment_augmenter,
        merger.template_analysis.comment_augmenter(owners: merger.template_analysis.statements),
      )
      merger.instance_variable_set(
        :@dest_comment_augmenter,
        merger.dest_analysis.comment_augmenter(owners: [dest_first, merger.dest_analysis.statements[2]]),
      )

      emission = support.emit_matched_template_node(
        result: result,
        template_node: template_first,
        dest_node: dest_first,
      )

      expect(emission).to eq({last_emitted_dest_line: 7})
      expect(result.to_s).to eq(<<~RUBY)
        def first_method
          :template
        end

        # trailing note

        # docs for removed second_method
      RUBY
    end

    it "emits template trailing blank line when dest is missing it (restores dropped blank)" do
      # Regression: a prior merge can drop a blank line that exists in the template.
      # On re-merge, emit_matched_template_node should restore it from the template.
      template = <<~RUBY
        x = 1

        y = 2
      RUBY

      # Dest is missing the blank line between x and y (was dropped in a prior merge)
      dest = <<~RUBY
        x = 0
        y = 0
      RUBY

      merger = merger_for(template, dest, preference: :template, add_template_only_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emission = support.emit_matched_template_node(
        result: result,
        template_node: first_node(merger, :template),
        dest_node: first_node(merger, :destination),
      )

      # last_emitted_dest_line advances to dest trailing position (dest end_line + 1 = 2)
      expect(emission).to eq({last_emitted_dest_line: 2})
      expect(result.to_s).to eq("x = 1\n\n")
    end

    it "does not double-emit trailing blank when both template and dest have it" do
      template = <<~RUBY
        x = 1

        y = 2
      RUBY

      dest = <<~RUBY
        x = 0

        y = 0
      RUBY

      merger = merger_for(template, dest, preference: :template, add_template_only_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emission = support.emit_matched_template_node(
        result: result,
        template_node: first_node(merger, :template),
        dest_node: first_node(merger, :destination),
      )

      expect(emission).to eq({last_emitted_dest_line: 2})
      expect(result.to_s).to eq("x = 1\n\n")
    end

    it "does not leak a destination trailing blank line before an immediately-following template-only sibling" do
      template = <<~RUBY
        x = 1
        y = 2
        z = 3
      RUBY

      dest = <<~RUBY
        x = 0

        z = 0
      RUBY

      merger = merger_for(template, dest, preference: :template, add_template_only_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emission = support.emit_matched_template_node(
        result: result,
        template_node: first_node(merger, :template),
        dest_node: first_node(merger, :destination),
      )

      expect(emission).to eq({last_emitted_dest_line: nil})
      expect(result.to_s).to eq(<<~RUBY)
        x = 1
      RUBY
    end
  end

  describe "#emit_node" do
    it "emits node source and trailing separator blank line with template provenance" do
      source = <<~RUBY
        def example
          :body
        end

        EXTRA = true
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: first_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq("def example\n  :body\nend\n\n")
      expect(result.line_metadata.map { |meta| meta[:template_line] }).to eq([1, 2, 3, 4])
    end

    it "does not duplicate the prefix separator after stripped template magic comments" do
      template = <<~RUBY
        # coding: utf-8
        # frozen_string_literal: true

        # docs
        x = 1
      RUBY

      merger = merger_for(template, "# frozen_string_literal: true\n\nx = 0\n")
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      result.add_line("# frozen_string_literal: true", decision: Prism::Merge::MergeResult::DECISION_KEPT_DEST, dest_line: 1)
      result.add_line("", decision: Prism::Merge::MergeResult::DECISION_KEPT_DEST, dest_line: 2)
      merger.instance_variable_set(:@dest_prefix_comment_lines, Set[1, 2])

      support.emit_node(
        result: result,
        node: first_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq(<<~RUBY)
        # frozen_string_literal: true

        # docs
        x = 1
      RUBY
    end

    it "preserves the template blank line before a template-only leading comment block" do
      source = <<~RUBY
        x = 1

        # docs
        y = 2
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      result.add_line("x = 1", decision: Prism::Merge::MergeResult::DECISION_KEPT_TEMPLATE, template_line: 1)

      support.emit_node(
        result: result,
        node: second_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq(<<~RUBY)
        x = 1

        # docs
        y = 2
      RUBY
    end

    it "does not duplicate the separator before a template-only leading comment block when siblings are emitted sequentially" do
      source = <<~RUBY
        x = 1

        # docs
        y = 2
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: first_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )
      support.emit_node(
        result: result,
        node: second_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq(source)
    end

    it "preserves full trailing postlude blank-line runs for comment-free nodes" do
      source = <<~RUBY
        def example
          :body
        end


      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: first_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq("def example\n  :body\nend\n\n\n")
      expect(result.line_metadata.map { |meta| meta[:template_line] }).to eq([1, 2, 3, 4, 5])
    end

    it "re-attaches owned inline comments for partial same-line destination nodes" do
      template = <<~RUBY
        shared_call
      RUBY

      dest = <<~RUBY
        shared_call; dest_only_call # keep this
      RUBY

      merger = merger_for(template, dest)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: second_node(merger, :destination),
        analysis: merger.dest_analysis,
        source: :destination,
      )

      expect(result.to_s).to eq("dest_only_call # keep this\n")
      expect(result.line_metadata.first[:dest_line]).to eq(1)
    end

    it "preserves indentation for partial same-line destination nodes split out of an indented scope" do
      template = <<~RUBY
        class Config
          shared_call
        end
      RUBY

      dest = <<~RUBY
        class Config
          shared_call; dest_only_call
        end
      RUBY

      merger = merger_for(template, dest)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      nested_dest_node = merger.dest_analysis.statements.first.body.body[1]

      support.emit_node(
        result: result,
        node: nested_dest_node,
        analysis: merger.dest_analysis,
        source: :destination,
      )

      expect(result.to_s).to eq("  dest_only_call\n")
      expect(result.line_metadata.first[:dest_line]).to eq(2)
    end

    it "emits template external trailing comments when adding a template node" do
      source = <<~RUBY
        def example
          :body
        end

        # trailing note
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: first_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq("def example\n  :body\nend\n# trailing note\n")
      expect(result.line_metadata.map { |meta| meta[:template_line] }).to eq([1, 2, 3, 5])
    end
  end

  describe "#emit_removed_destination_node_comments" do
    it "promotes leading, inline, and external trailing comments for a removed destination-only node" do
      template = <<~RUBY
        KEEP = true
      RUBY

      dest = <<~RUBY
        # docs for old setting
        OLD = true # keep inline

        # trailing note
        KEEP = true
      RUBY

      merger = merger_for(template, dest, remove_template_missing_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      removed_node = first_node(merger, :destination)

      emission = support.emit_removed_destination_node_comments(
        result: result,
        node: removed_node,
        analysis: merger.dest_analysis,
      )

      expect(emission).to eq({
        last_emitted_dest_line: 2,
        emitted_removed_owner_comments: true,
      })
      expect(result.to_s).to eq("# docs for old setting\n# keep inline\n")
    end

    it "promotes external trailing comments for a removed destination-only node when no orphan re-home applies" do
      template = ""

      dest = <<~RUBY
        # docs for old setting
        OLD = true # keep inline

        # trailing note
      RUBY

      merger = merger_for(template, dest, remove_template_missing_nodes: true)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      removed_node = first_node(merger, :destination)

      emission = support.emit_removed_destination_node_comments(
        result: result,
        node: removed_node,
        analysis: merger.dest_analysis,
      )

      expect(emission).to eq({
        last_emitted_dest_line: 4,
        emitted_removed_owner_comments: true,
      })
      expect(result.to_s).to eq("# docs for old setting\n# keep inline\n\n# trailing note\n")
    end
  end

  describe "removed-owner corruption handling" do
    let(:dest) do
      <<~RUBY
        # docs for old setting
        OLD = true

        # trailing note
      RUBY
    end
    let(:comments) { first_node(merger, :destination).location.leading_comments }
    let(:trailing_comments) { merger.send(:external_trailing_comments_for, first_node(merger, :destination)) }
    let(:support) { described_class.new(merger: merger) }
    let(:rehomed_orphan_lines) { Set[1, 4] }

    describe "#filter_rehomed_removed_owner_comments" do
      context "with default healing" do
        let(:merger) { merger_for("", dest, corruption_handling: :heal, remove_template_missing_nodes: true) }

        it "filters comments already rehomed as orphan regions" do
          filtered_leading = support.send(
            :filter_rehomed_removed_owner_comments,
            comments,
            rehomed_orphan_lines: rehomed_orphan_lines,
            comment_role: :leading,
          )
          filtered_trailing = support.send(
            :filter_rehomed_removed_owner_comments,
            trailing_comments,
            rehomed_orphan_lines: rehomed_orphan_lines,
            comment_role: :external_trailing,
          )

          expect(filtered_leading).to eq([])
          expect(filtered_trailing).to eq([])
        end
      end

      context "with skip handling" do
        let(:merger) { merger_for("", dest, corruption_handling: :skip, remove_template_missing_nodes: true) }

        it "preserves the raw removed-owner comments" do
          filtered_leading = support.send(
            :filter_rehomed_removed_owner_comments,
            comments,
            rehomed_orphan_lines: rehomed_orphan_lines,
            comment_role: :leading,
          )
          filtered_trailing = support.send(
            :filter_rehomed_removed_owner_comments,
            trailing_comments,
            rehomed_orphan_lines: rehomed_orphan_lines,
            comment_role: :external_trailing,
          )

          expect(filtered_leading).to eq(comments)
          expect(filtered_trailing).to eq(trailing_comments)
        end
      end

      context "with warn handling" do
        let(:merger) { merger_for("", dest, corruption_handling: :warn, remove_template_missing_nodes: true) }

        it "warns without filtering" do
          expect do
            filtered_leading = support.send(
              :filter_rehomed_removed_owner_comments,
              comments,
              rehomed_orphan_lines: rehomed_orphan_lines,
              comment_role: :leading,
            )
            filtered_trailing = support.send(
              :filter_rehomed_removed_owner_comments,
              trailing_comments,
              rehomed_orphan_lines: rehomed_orphan_lines,
              comment_role: :external_trailing,
            )

            expect(filtered_leading).to eq(comments)
            expect(filtered_trailing).to eq(trailing_comments)
          end.to output(/Suspected corruption \(removed_owner_comment_overlap\)/).to_stderr
        end
      end

      context "with error handling" do
        let(:merger) { merger_for("", dest, corruption_handling: :error, remove_template_missing_nodes: true) }

        it "raises instead of filtering" do
          expect do
            support.send(
              :filter_rehomed_removed_owner_comments,
              comments,
              rehomed_orphan_lines: rehomed_orphan_lines,
              comment_role: :leading,
            )
          end.to raise_error(Prism::Merge::CorruptionDetectedError, /removed_owner_comment_overlap/)
        end
      end
    end
  end

  describe "overlap corruption handling" do
    let(:source) do
      <<~RUBY
        alpha = 1
        # Shared docs
        beta = 2
      RUBY
    end

    let(:comments) { second_node(merger, :template).location.leading_comments }
    let(:dest_comments) { second_node(merger, :destination).location.leading_comments }
    let(:support) { described_class.new(merger: merger) }

    describe "#filter_already_emitted_leading_comments" do
      context "with default healing" do
        let(:merger) { merger_for(source, source, corruption_handling: :heal) }

        it "filters overlapping comments" do
          merger.instance_variable_set(:@emitted_dest_leading_texts, Set[comments.first.slice.strip])

          filtered, last_filtered_line = support.send(:filter_already_emitted_leading_comments, comments)

          expect(filtered).to eq([])
          expect(last_filtered_line).to eq(2)
        end
      end

      context "with skip handling" do
        let(:merger) { merger_for(source, source, corruption_handling: :skip) }

        it "preserves the raw overlapping comments" do
          merger.instance_variable_set(:@emitted_dest_leading_texts, Set[comments.first.slice.strip])

          filtered, last_filtered_line = support.send(:filter_already_emitted_leading_comments, comments)

          expect(filtered).to eq(comments)
          expect(last_filtered_line).to be_nil
        end
      end

      context "with warn handling" do
        let(:merger) { merger_for(source, source, corruption_handling: :warn) }

        it "warns without filtering" do
          merger.instance_variable_set(:@emitted_dest_leading_texts, Set[comments.first.slice.strip])

          expect do
            filtered, last_filtered_line = support.send(:filter_already_emitted_leading_comments, comments)
            expect(filtered).to eq(comments)
            expect(last_filtered_line).to be_nil
          end.to output(/Suspected corruption \(comment_ownership_overlap\)/).to_stderr
        end
      end

      context "with error handling" do
        let(:merger) { merger_for(source, source, corruption_handling: :error) }

        it "raises instead of filtering" do
          merger.instance_variable_set(:@emitted_dest_leading_texts, Set[comments.first.slice.strip])

          expect do
            support.send(:filter_already_emitted_leading_comments, comments)
          end.to raise_error(Prism::Merge::CorruptionDetectedError, /comment_ownership_overlap/)
        end
      end
    end

    describe "#filter_emitted_template_leading_comments" do
      context "with default healing" do
        let(:merger) { merger_for(source, source, corruption_handling: :heal) }

        it "records skipped destination prefix lines for healed overlaps" do
          merger.instance_variable_set(:@emitted_template_leading_texts, Set[dest_comments.first.slice.strip])
          merger.instance_variable_set(:@dest_prefix_comment_lines, Set.new)

          filtered, last_filtered_line = support.send(:filter_emitted_template_leading_comments, dest_comments)

          expect(filtered).to eq([])
          expect(last_filtered_line).to eq(2)
          expect(merger.instance_variable_get(:@dest_prefix_comment_lines)).to eq(Set[2])
        end
      end

      context "with skip handling" do
        let(:merger) { merger_for(source, source, corruption_handling: :skip) }

        it "leaves destination prefix tracking untouched" do
          merger.instance_variable_set(:@emitted_template_leading_texts, Set[dest_comments.first.slice.strip])
          merger.instance_variable_set(:@dest_prefix_comment_lines, Set.new)

          filtered, last_filtered_line = support.send(:filter_emitted_template_leading_comments, dest_comments)

          expect(filtered).to eq(dest_comments)
          expect(last_filtered_line).to be_nil
          expect(merger.instance_variable_get(:@dest_prefix_comment_lines)).to eq(Set.new)
        end
      end
    end
  end
end
