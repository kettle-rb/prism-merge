# frozen_string_literal: true

require "spec_helper"

RSpec.describe "FreezeNode Edge Cases" do
  describe "freeze block spanning multiple node types" do
    context "when freeze block starts mid-comment and spans into code" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # This is documentation
          # More documentation
          def method_one
            "one"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # This is documentation
          # prism-merge:freeze
          # More documentation
          def method_one
            "customized"
          end
          # prism-merge:unfreeze
        RUBY
      end

      it "handles freeze block that starts in comments and continues through code" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        # The entire freeze block should be preserved from destination
        expect(result).to include("def method_one")
        expect(result).to include('"customized"')
        expect(result).to include("# More documentation")
        expect(result).not_to include('"one"')
      end
    end

    context "when freeze block contains partial node (unclosed)" do
      let(:dest_code_unclosed_start) do
        <<~RUBY
          # frozen_string_literal: true

          # prism-merge:freeze
          def method_one
            "value"
          # prism-merge:unfreeze
          end
        RUBY
      end

      let(:dest_code_unclosed_end) do
        <<~RUBY
          # frozen_string_literal: true

          def method_one
          # prism-merge:freeze
            "value"
          end
          # prism-merge:unfreeze
        RUBY
      end

      it "raises an error when freeze block contains unclosed node (def without end inside)" do
        expect {
          Prism::Merge::FileAnalysis.new(dest_code_unclosed_start)
        }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError, /incomplete nodes/)
      end

      it "raises an error when freeze block starts inside a node" do
        expect {
          Prism::Merge::FileAnalysis.new(dest_code_unclosed_end)
        }.to raise_error(Prism::Merge::FreezeNode::InvalidStructureError, /incomplete nodes/)
      end
    end

    context "when freeze block contains multiple complete nodes" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          CONST = "template"
          
          def method_one
            "template"
          end
          
          def method_two
            "template"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # prism-merge:freeze
          CONST = "dest"
          
          def method_one
            "dest custom"
          end
          
          def method_two
            "dest custom"
          end
          # prism-merge:unfreeze
        RUBY
      end

      it "preserves entire freeze block as a unit from destination" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('CONST = "dest"')
        expect(result).to include("def method_one")
        expect(result).to include('"dest custom"')
        expect(result).to include("def method_two")
        expect(result).not_to include('"template"')
      end
    end

    context "when freeze block is only comments" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # Standard header
          # More info
          
          CONST = "template"
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # prism-merge:freeze
          # Custom header
          # Custom info
          # prism-merge:unfreeze
          
          CONST = "dest"
        RUBY
      end

      it "preserves comment-only freeze block from destination" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include("# Custom header")
        expect(result).to include("# Custom info")
        expect(result).not_to include("# Standard header")
        expect(result).not_to include("# More info")
      end
    end

    context "when freeze markers are within a method body" do
      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          def method_one
            # prism-merge:freeze
            value = "custom"
            # prism-merge:unfreeze
            value
          end
        RUBY
      end

      it "allows freeze blocks inside method bodies" do
        # The method_one node spans lines 3-8, and the freeze block is lines 4-6
        # This is valid because DefNode is allowed to contain freeze blocks
        # (freeze blocks can protect portions of method implementations)
        expect {
          Prism::Merge::FileAnalysis.new(dest_code)
        }.not_to raise_error
      end
    end
  end

  describe "FreezeNode relationship to comments" do
    context "when comments exist near freeze blocks" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # Comment before constant
          
          CONST = "template"
          
          # Comment after constant
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # Comment before freeze block
          
          # prism-merge:freeze
          CONST = "dest"
          # prism-merge:unfreeze
          
          # Comment after freeze block
        RUBY
      end

      it "treats comments and freeze blocks appropriately" do
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        # V2: No standalone CommentNodes - comments attach to nodes
        # Should have freeze node
        freeze_nodes = dest_analysis.statements.select { |s| s.is_a?(Prism::Merge::FreezeNode) }
        expect(freeze_nodes.length).to eq(1)

        # Comments attach to the freeze node or surrounding nodes via Prism's native mechanism
        # The "Comment before freeze block" would attach as leading comment to freeze node
        freeze_node = freeze_nodes.first
        expect(freeze_node).to be_a(Prism::Merge::FreezeNode)
      end
    end
  end
end
