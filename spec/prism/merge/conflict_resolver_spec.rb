# frozen_string_literal: true

RSpec.describe Prism::Merge::ConflictResolver do
  let(:template_content) do
    <<~RUBY
      # frozen_string_literal: true

      VERSION = "2.0.0"

      def template_method
        puts "template"
      end

      def shared_method
        puts "template version"
      end
    RUBY
  end

  let(:dest_content) do
    <<~RUBY
      # frozen_string_literal: true

      VERSION = "1.0.0"

      def shared_method
        puts "destination version"
      end

      def dest_method
        puts "destination"
      end
    RUBY
  end

  let(:template_analysis) { Prism::Merge::FileAnalysis.new(template_content) }
  let(:dest_analysis) { Prism::Merge::FileAnalysis.new(dest_content) }

  describe "#initialize" do
    it "creates resolver with default preferences" do
      resolver = described_class.new(template_analysis, dest_analysis)

      expect(resolver.template_analysis).to eq(template_analysis)
      expect(resolver.dest_analysis).to eq(dest_analysis)
      expect(resolver.signature_match_preference).to be(:destination)
      expect(resolver.add_template_only_nodes).to be(false)
    end

    it "creates resolver with custom preferences" do
      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        signature_match_preference: :template,
        add_template_only_nodes: true,
      )

      expect(resolver.signature_match_preference).to be(:template)
      expect(resolver.add_template_only_nodes).to be(true)
    end
  end

  describe "#resolve" do
    let(:result) { Prism::Merge::MergeResult.new }

    context "with template-only nodes and add_template_only_nodes: true" do
      it "adds template-only nodes to result" do
        # Use SmartMerger instead of calling resolver directly
        # because signature matching is handled at the SmartMerger level
        merger = Prism::Merge::SmartMerger.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )

        result_text = merger.merge

        # Should include template-only method
        expect(result_text).to include("def template_method")

        # Should include shared method (template version due to preference)
        expect(result_text).to include("def shared_method")
        expect(result_text).to include('puts "template version"')

        # Should include dest-only method
        expect(result_text).to include("def dest_method")
      end
    end

    context "with template-only nodes and add_template_only_nodes: false" do
      it "skips template-only nodes" do
        # Use SmartMerger instead of calling resolver directly
        merger = Prism::Merge::SmartMerger.new(
          template_content,
          dest_content,
          signature_match_preference: :destination,
          add_template_only_nodes: false,
        )

        result_text = merger.merge

        # Should NOT include template-only method
        expect(result_text).not_to include("def template_method")

        # Should include shared method (destination version due to preference)
        expect(result_text).to include("def shared_method")
        expect(result_text).to include('puts "destination version"')

        # Should include dest-only method
        expect(result_text).to include("def dest_method")
      end
    end

    context "with freeze block in destination boundary" do
      let(:template_with_code) do
        <<~RUBY
          # frozen_string_literal: true

          REGULAR = "template"
        RUBY
      end

      let(:dest_with_freeze_in_boundary) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          CUSTOM = "destination"
          SECRET = "preserved"
          # kettle-dev:unfreeze

          REGULAR = "destination"
        RUBY
      end

      it "preserves freeze block content from destination" do
        # Use SmartMerger for integration test
        merger = Prism::Merge::SmartMerger.new(
          template_with_code,
          dest_with_freeze_in_boundary,
          freeze_token: "kettle-dev",
        )

        result_text = merger.merge

        # Destination freeze block should be preserved
        expect(result_text).to include('CUSTOM = "destination"')
        expect(result_text).to include('SECRET = "preserved"')
        expect(result_text).to include("kettle-dev:freeze")
        expect(result_text).to include("kettle-dev:unfreeze")
      end
    end

    context "with empty boundaries" do
      it "handles empty template range" do
        empty_template = "# frozen_string_literal: true\n"
        full_dest = "# frozen_string_literal: true\n\nVERSION = \"1.0.0\"\n"

        template_analysis = Prism::Merge::FileAnalysis.new(empty_template)
        dest_analysis = Prism::Merge::FileAnalysis.new(full_dest)

        resolver = described_class.new(template_analysis, dest_analysis)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        boundaries.each do |boundary|
          resolver.resolve(boundary, result)
        end

        result_text = result.to_s
        expect(result_text).to include('VERSION = "1.0.0"')
      end

      it "handles empty destination range" do
        full_template = "# frozen_string_literal: true\n\nVERSION = \"2.0.0\"\n"
        empty_dest = "# frozen_string_literal: true\n"

        template_analysis = Prism::Merge::FileAnalysis.new(full_template)
        dest_analysis = Prism::Merge::FileAnalysis.new(empty_dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true,
        )
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        boundaries.each do |boundary|
          resolver.resolve(boundary, result)
        end

        result_text = result.to_s
        expect(result_text).to include('VERSION = "2.0.0"')
      end

      it "handles both ranges empty" do
        empty_template = "# frozen_string_literal: true\n"
        empty_dest = "# frozen_string_literal: true\n"

        template_analysis = Prism::Merge::FileAnalysis.new(empty_template)
        dest_analysis = Prism::Merge::FileAnalysis.new(empty_dest)

        resolver = described_class.new(template_analysis, dest_analysis)

        # Create an empty boundary
        boundary = Prism::Merge::FileAligner::Boundary.new(nil, nil, nil, nil)

        # Should not error
        expect { resolver.resolve(boundary, result) }.not_to raise_error
      end
    end

    context "with boundary containing only whitespace" do
      it "handles resolution when boundary has only blank lines" do
        template = <<~RUBY
          def method_a
            "a"
          end


          def method_b
            "b"
          end
        RUBY

        destination = <<~RUBY
          def method_a
            "a"
          end
          def method_b
            "b"
          end
        RUBY

        # The extra blank lines in template create a boundary with no nodes
        merger = Prism::Merge::SmartMerger.new(template, destination)
        result_text = merger.merge

        # Should successfully merge without errors
        expect(result_text).to include("def method_a")
        expect(result_text).to include("def method_b")
      end
    end

    context "with empty content lines in boundary" do
      it "handles boundary where content lines array is empty" do
        template = <<~RUBY
          # frozen_string_literal: true
          def method
            "template"
          end
        RUBY

        destination = <<~RUBY
          # frozen_string_literal: true

          def method
            "destination"
          end
        RUBY

        merger = Prism::Merge::SmartMerger.new(
          template,
          destination,
          signature_match_preference: :destination,
        )
        result_text = merger.merge

        expect(result_text).to include("def method")
      end
    end

    context "with signature_match_preference: :template in boundary resolution" do
      it "uses template version for matched nodes within boundaries" do
        # This test directly creates a boundary scenario with matching signatures
        # to test the resolver's :template preference path
        template = <<~RUBY
          def method_a
            "template a"
          end

          def method_b
            "template b"
          end
        RUBY

        destination = <<~RUBY
          def method_a
            "destination a"
          end

          def method_b
            "destination b"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(destination)

        # Create resolver with :template preference
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )

        # Create a boundary that covers both methods
        # This simulates what would happen if the aligner didn't create anchors
        boundary = Prism::Merge::FileAligner::Boundary.new(1..7, 1..7, nil, nil)
        result = Prism::Merge::MergeResult.new

        resolver.resolve(boundary, result)

        result_text = result.to_s

        # With :template preference, template versions should be used
        expect(result_text).to include('"template a"')
        expect(result_text).to include('"template b"')
        expect(result_text).not_to include('"destination a"')
        expect(result_text).not_to include('"destination b"')
      end

      it "handles matched nodes with leading comments using :template preference" do
        template = <<~RUBY
          # Comment for method
          def my_method
            "template"
          end
        RUBY

        destination = <<~RUBY
          # Different comment
          def my_method
            "destination"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(destination)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          signature_match_preference: :template,
        )

        boundary = Prism::Merge::FileAligner::Boundary.new(1..4, 1..4, nil, nil)
        result = Prism::Merge::MergeResult.new

        resolver.resolve(boundary, result)
        result_text = result.to_s

        expect(result_text).to include('"template"')
      end
    end

    context "with nil template_line_range" do
      it "handles boundary with nil template range" do
        # Create a boundary manually with nil template range
        template = "# frozen_string_literal: true\n"
        dest = "# frozen_string_literal: true\n\nVERSION = \"1.0\"\n"

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: false,
        )

        # Create boundary with nil template range (destination-only content)
        boundary = Prism::Merge::FileAligner::Boundary.new(nil, 2..3, nil, nil)
        result = Prism::Merge::MergeResult.new

        expect { resolver.resolve(boundary, result) }.not_to raise_error
      end
    end

    context "with empty sorted_nodes after processing" do
      it "handles boundaries where all nodes are filtered out" do
        # A boundary with only comments (no actual nodes)
        template = <<~RUBY
          # Just a comment
          # Another comment
        RUBY

        dest = <<~RUBY
          # Different comment
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(template_analysis, dest_analysis)
        boundary = Prism::Merge::FileAligner::Boundary.new(1..2, 1..1, nil, nil)
        result = Prism::Merge::MergeResult.new

        expect { resolver.resolve(boundary, result) }.not_to raise_error
      end
    end

    context "with freeze block content lines empty" do
      it "handles freeze blocks with markers but empty content" do
        template = <<~RUBY
          gem "rails"
        RUBY

        dest = <<~RUBY
          # kettle-dev:freeze
          # kettle-dev:unfreeze
          gem "rails"
        RUBY

        merger = Prism::Merge::SmartMerger.new(
          template,
          dest,
          freeze_token: "kettle-dev",
        )
        result_text = merger.merge

        expect(result_text).to include("kettle-dev:freeze")
        expect(result_text).to include("kettle-dev:unfreeze")
      end
    end

    context "with node without signature in boundary" do
      it "handles nodes that have nil signatures" do
        # Using expressions that don't generate signatures
        template = <<~RUBY
          1 + 2
          "hello"
        RUBY

        dest = <<~RUBY
          3 + 4
          "world"
        RUBY

        # Custom generator that returns nil for everything
        nil_gen = ->(_node) { nil }

        merger = Prism::Merge::SmartMerger.new(
          template,
          dest,
          signature_generator: nil_gen,
          signature_match_preference: :destination,
        )

        # Should not error even with nil signatures everywhere
        expect { merger.merge }.not_to raise_error
      end
    end

    context "with add_content_to_result edge cases" do
      it "handles empty content lines array" do
        # This tests line 137 - content[:lines].empty? returning true
        template = "# frozen_string_literal: true\n"
        dest = "# frozen_string_literal: true\n"

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(template_analysis, dest_analysis)

        # Create a boundary with empty line range (no actual lines)
        # This will result in empty content[:lines]
        boundary = Prism::Merge::FileAligner::Boundary.new(2..1, 2..1, nil, nil)
        result = Prism::Merge::MergeResult.new

        # Should handle gracefully
        expect { resolver.resolve(boundary, result) }.not_to raise_error
      end
    end

    context "with nodes having leading comments on dest" do
      it "uses dest node leading comment line for next_content_start" do
        template = <<~RUBY
          def method_a
            "a"
          end

          def method_b
            "b"
          end
        RUBY

        destination = <<~RUBY
          def method_a
            "a dest"
          end

          # Comment before method_b
          def method_b
            "b dest"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(destination)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          signature_match_preference: :destination,
        )

        # Process boundary covering all content
        boundary = Prism::Merge::FileAligner::Boundary.new(1..7, 1..8, nil, nil)
        result = Prism::Merge::MergeResult.new

        resolver.resolve(boundary, result)
        result_text = result.to_s

        # Comment should be preserved
        expect(result_text).to include("Comment before method_b")
      end
    end

    context "with trailing non-blank lines" do
      it "stops at first non-blank line when finding trailing blanks" do
        template = <<~RUBY
          def method_a
            "a"
          end
          # Not a blank line
          def method_b
            "b"
          end
        RUBY

        destination = <<~RUBY
          def method_a
            "a dest"
          end
          # Not blank in dest either
          def method_b
            "b dest"
          end
        RUBY

        template_analysis = Prism::Merge::FileAnalysis.new(template)
        dest_analysis = Prism::Merge::FileAnalysis.new(destination)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          signature_match_preference: :destination,
        )

        boundary = Prism::Merge::FileAligner::Boundary.new(1..7, 1..7, nil, nil)
        result = Prism::Merge::MergeResult.new

        resolver.resolve(boundary, result)
        result_text = result.to_s

        expect(result_text).to include("def method_a")
        expect(result_text).to include("def method_b")
      end
    end
  end
end
