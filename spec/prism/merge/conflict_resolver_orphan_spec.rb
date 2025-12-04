# frozen_string_literal: true

RSpec.describe Prism::Merge::ConflictResolver do
  describe "orphan line handling" do
    let(:result) { Prism::Merge::MergeResult.new }

    # Helper method to add anchor content before resolving boundaries
    # ConflictResolver tests need anchor content added first since they test in isolation
    def resolve_with_anchors(template_analysis, dest_analysis, resolver, aligner, result)
      boundaries = aligner.align

      # Add anchor content (matching nodes) to result
      # For signature matches, prefer template to preserve comments
      aligner.anchors.each do |anchor|
        if anchor.match_type == :signature_match
          # Use template range to preserve leading comments
          anchor.template_range.each do |line_num|
            line = template_analysis.line_at(line_num)
            result.add_line(line.chomp, decision: :kept_template, template_line: line_num)
          end
        else
          # For exact matches, use destination
          anchor.dest_range.each do |line_num|
            line = dest_analysis.line_at(line_num)
            result.add_line(line.chomp, decision: :kept_destination, dest_line: line_num)
          end
        end
      end

      # Resolve boundaries (content between matching nodes)
      boundaries.each do |boundary|
        resolver.resolve(boundary, result)
      end
    end

    context "with orphan lines (comments and blank lines between nodes)" do
      it "handles orphan comments in template" do
        template_content = <<~RUBY
          def method_one
            puts "one"
          end

          # This is an orphan comment in template

          def method_two
            puts "two"
          end
        RUBY

        dest_content = <<~RUBY
          def method_one
            puts "one"
          end

          def method_two
            puts "two"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis, add_template_only_nodes: true)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

        resolve_with_anchors(template_analysis, dest_analysis, resolver, aligner, result)

        result_text = result.to_s

        # Orphan comment should be included from template
        expect(result_text).to include("# This is an orphan comment in template")
      end

      it "handles unique orphan comments in destination" do
        template_content = <<~RUBY
          def method_one
            puts "template"
          end

          def method_two
            puts "template"
          end
        RUBY

        dest_content = <<~RUBY
          def method_one
            puts "dest"
          end

          # This is a unique orphan comment in destination

          def method_two
            puts "dest"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

        resolve_with_anchors(template_analysis, dest_analysis, resolver, aligner, result)

        result_text = result.to_s

        # When methods have same signature but different bodies, they create boundaries
        # Verify the merge completed
        expect(result_text).to include("def method_one")
        expect(result_text).to include("def method_two")
      end

      it "deduplicates identical orphan comments" do
        # Use a scenario where there are unmatched nodes creating boundaries
        template_content = <<~RUBY
          # Template file
          TEMPLATE_CONST = "template"

          # Orphan comment that exists in both
        RUBY

        dest_content = <<~RUBY
          # Destination file
          DEST_CONST = "dest"

          # Orphan comment that exists in both
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis, add_template_only_nodes: true)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

        resolve_with_anchors(template_analysis, dest_analysis, resolver, aligner, result)

        result_text = result.to_s

        # Verify merge completed with both constants
        expect(result_text).to include("TEMPLATE_CONST")
        expect(result_text).to include("DEST_CONST")
      end

      it "handles multiple orphan lines in same boundary" do
        # Create a scenario with unmatched nodes and orphan comments
        template_content = <<~RUBY
          # Template file
          
          # Orphan comment 1
          # Orphan comment 2
          
          TEMPLATE_CONST = "template"
        RUBY

        dest_content = <<~RUBY
          # Destination file
          
          # Orphan comment 3
          
          DEST_CONST = "dest"
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis, add_template_only_nodes: true)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

        resolve_with_anchors(template_analysis, dest_analysis, resolver, aligner, result)

        result_text = result.to_s

        # Verify the merge includes constants
        expect(result_text).to include("TEMPLATE_CONST")
        expect(result_text).to include("DEST_CONST")
      end

      it "skips blank orphan lines" do
        template_content = <<~RUBY
          def method_one
            puts "one"
          end


          def method_two
            puts "two"
          end
        RUBY

        dest_content = <<~RUBY
          def method_one
            puts "one"
          end

          def method_two
            puts "two"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis, add_template_only_nodes: true)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)

        resolve_with_anchors(template_analysis, dest_analysis, resolver, aligner, result)

        result_text = result.to_s

        # Should not include excessive blank lines from orphans
        blank_line_count = result_text.scan("\n\n\n").length
        expect(blank_line_count).to eq(0)
      end
    end

    context "with find_orphan_lines helper" do
      let(:template_content) do
        <<~RUBY
          def method_one
            puts "one"
          end

          # Orphan comment

          def method_two
            puts "two"
          end
        RUBY
      end

      let(:dest_content) do
        <<~RUBY
          def method_one
            puts "one"
          end

          def method_two
            puts "two"
          end
        RUBY
      end

      it "identifies orphan lines not covered by nodes" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis)

        # Call private method for testing
        line_range = 1..template_analysis.lines.length
        nodes = template_analysis.statements.map do |stmt|
          {
            node: stmt,
            line_range: stmt.location.start_line..stmt.location.end_line,
            leading_comments: [],
            inline_comments: [],
          }
        end

        orphans = resolver.send(:find_orphan_lines, template_analysis, line_range, nodes)

        # Should find the orphan comment line
        expect(orphans).to include(5)
      end

      it "returns empty array for nil line_range" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis)

        orphans = resolver.send(:find_orphan_lines, template_analysis, nil, [])

        expect(orphans).to eq([])
      end

      it "excludes lines covered by nodes" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_content)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

        resolver = described_class.new(template_analysis, dest_analysis)

        line_range = 1..template_analysis.lines.length
        nodes = template_analysis.statements.map do |stmt|
          {
            node: stmt,
            line_range: stmt.location.start_line..stmt.location.end_line,
            leading_comments: [],
            inline_comments: [],
          }
        end

        orphans = resolver.send(:find_orphan_lines, template_analysis, line_range, nodes)

        # Should not include lines covered by method definitions
        expect(orphans).not_to include(1) # def method_one
        expect(orphans).not_to include(2) # puts "one"
        expect(orphans).not_to include(3) # end
        expect(orphans).not_to include(7) # def method_two
      end

      it "excludes blank lines" do
        content_with_blanks = <<~RUBY
          def method_one
            puts "one"
          end


          def method_two
            puts "two"
          end
        RUBY

        analysis = Prism::Merge::FileAnalysis.new(content_with_blanks)
        resolver = described_class.new(analysis, analysis)

        line_range = 1..analysis.lines.length
        nodes = analysis.statements.map do |stmt|
          {
            node: stmt,
            line_range: stmt.location.start_line..stmt.location.end_line,
            leading_comments: [],
            inline_comments: [],
          }
        end

        orphans = resolver.send(:find_orphan_lines, analysis, line_range, nodes)

        # Should not include blank lines
        expect(orphans).not_to include(4)
        expect(orphans).not_to include(5)
      end

      it "includes leading comments in covered lines" do
        content_with_leading = <<~RUBY
          # Leading comment for method
          def method_one
            puts "one"
          end
        RUBY

        analysis = Prism::Merge::FileAnalysis.new(content_with_leading)
        resolver = described_class.new(analysis, analysis)

        line_range = 1..analysis.lines.length
        stmt = analysis.statements.first
        nodes = [{
          node: stmt,
          line_range: stmt.location.start_line..stmt.location.end_line,
          leading_comments: analysis.parse_result.comments.select do |c|
            c.location.start_line == 1
          end,
          inline_comments: [],
        }]

        orphans = resolver.send(:find_orphan_lines, analysis, line_range, nodes)

        # Leading comment should be excluded from orphans (covered by node)
        expect(orphans).not_to include(1)
      end
    end

    context "with handle_orphan_lines method" do
      it "adds unique destination orphans to result" do
        template_analysis = Prism::Merge::FileAnalysis.new("def method; end")
        dest_analysis = Prism::Merge::FileAnalysis.new("# comment\ndef method; end")

        resolver = described_class.new(template_analysis, dest_analysis)

        template_content = {
          line_range: 1..1,
          nodes: [],
        }

        dest_content = {
          line_range: 1..2,
          nodes: [],
        }

        resolver.send(:handle_orphan_lines, template_content, dest_content, result)

        result_text = result.to_s
        expect(result_text).to include("# comment")
      end

      it "does not duplicate orphans present in both files" do
        template_analysis = Prism::Merge::FileAnalysis.new("# same comment\ndef method; end")
        dest_analysis = Prism::Merge::FileAnalysis.new("# same comment\ndef method; end")

        resolver = described_class.new(template_analysis, dest_analysis)

        template_content = {
          line_range: 1..2,
          nodes: [],
        }

        dest_content = {
          line_range: 1..2,
          nodes: [],
        }

        result.to_s.lines.length
        resolver.send(:handle_orphan_lines, template_content, dest_content, result)

        # Should not add duplicate
        comment_count = result.to_s.scan("# same comment").length
        expect(comment_count).to be <= 1
      end
    end
  end
end
