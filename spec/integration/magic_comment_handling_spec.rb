# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Magic Comment and Directive Handling" do
  describe "magic comment filtering" do
    it "attaches regular comments to nodes via Prism" do
      content = <<~RUBY
        # frozen_string_literal: true
        # encoding: utf-8
        # warn_indent: true
        
        # This is a regular comment
        
        def method_one
          "one"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # V2: No CommentNodes. Comments attach to nodes via Prism's native mechanism.
      # Should have just the DefNode
      expect(analysis.statements.length).to eq(1)

      def_node = analysis.statements.first
      expect(def_node).to be_a(Prism::DefNode)

      # Prism attaches ALL comments including magic comments
      # This is expected behavior - magic comments are comments too
      expect(def_node.location.leading_comments.length).to eq(4) # 3 magic + 1 regular
      leading_text = def_node.location.leading_comments.map(&:slice).join
      expect(leading_text).to include("regular comment")
      expect(leading_text).to include("frozen_string_literal") # Prism includes magic comments
      expect(leading_text).to include("encoding")
    end

    it "preserves magic comments in merged output" do
      template = <<~RUBY
        # frozen_string_literal: true
        
        def method_one
          "template"
        end
      RUBY

      destination = <<~RUBY
        # frozen_string_literal: true
        # encoding: utf-8
        
        def method_one
          "dest"
        end
      RUBY

      merger = Prism::Merge::SmartMerger.new(template, destination)
      result = merger.merge

      # Magic comments should be preserved
      expect(result).to include("# frozen_string_literal: true")
    end
  end

  describe "directive comment filtering" do
    it "attaches directive and regular comments appropriately" do
      content = <<~RUBY
        # frozen_string_literal: true
        
        # rubocop:disable Metrics/MethodLength
        def long_method
          # This is a regular comment inside
          line1
          line2
        end
        # rubocop:enable Metrics/MethodLength
        
        # steep:ignore
        def another_method
          "value"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # V2: No standalone CommentNodes - comments attach to code nodes
      # Should have 2 DefNodes
      expect(analysis.statements.length).to eq(2)
      expect(analysis.statements.all? { |s| s.is_a?(Prism::DefNode) }).to be true

      # First method should have rubocop directive as leading comment
      first_method = analysis.statements.first
      leading_comments = first_method.location.leading_comments.map(&:slice).join
      expect(leading_comments).to include("rubocop:disable")

      # Second method should have steep directive as leading comment
      second_method = analysis.statements.last
      leading_comments = second_method.location.leading_comments.map(&:slice).join
      expect(leading_comments).to include("steep:ignore")
    end

    it "recognizes various directive patterns" do
      content = <<~RUBY
        # frozen_string_literal: true
        
        # rubocop:disable Layout/LineLength
        # sorbet: true
        # yard: hide
        # rdoc: markup
        # steep:ignore
        
        # Regular documentation comment
        
        def method_one
          "one"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # V2: All comments attach to the DefNode as leading comments
      expect(analysis.statements.length).to eq(1)
      def_node = analysis.statements.first

      # All the comments (directives and regular) should be leading comments
      leading_comments = def_node.location.leading_comments
      expect(leading_comments.length).to be >= 5

      leading_text = leading_comments.map(&:slice).join
      expect(leading_text).to include("Regular documentation")
      expect(leading_text).to include("rubocop:")
      expect(leading_text).to include("sorbet:")
    end
  end

  describe "freeze marker filtering" do
    it "creates FreezeNodes without treating markers as regular comments" do
      content = <<~RUBY
        # frozen_string_literal: true
        
        # Regular comment before
        
        # prism-merge:freeze
        CONST = "value"
        # prism-merge:unfreeze
        
        # Regular comment after
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # V2: No CommentNodes - should have FreezeNode and comments attach to adjacent nodes
      freeze_nodes = analysis.statements.select { |s| s.is_a?(Prism::Merge::FreezeNode) }
      expect(freeze_nodes.length).to eq(1)

      # Freeze node content includes the constant
      freeze_node = freeze_nodes.first
      expect(freeze_node.slice).to include("CONST")
      expect(freeze_node.slice).to include("prism-merge:freeze")
      expect(freeze_node.slice).to include("prism-merge:unfreeze")
    end
  end

  describe "mixed comment types" do
    it "correctly categorizes all comment types" do
      content = <<~RUBY
        # frozen_string_literal: true
        # encoding: utf-8
        
        # rubocop:disable Style/Documentation
        # This is actual documentation for the class
        class MyClass
          # prism-merge:freeze
          CUSTOM = "value"
          # prism-merge:unfreeze
          
          # steep:ignore
          def method_one
            # Comment inside method
            "one"
          end
        end
        # rubocop:enable Style/Documentation
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # V2: Should have ClassNode with FreezeNode inside it
      # No standalone CommentNodes
      freeze_nodes = analysis.freeze_blocks
      expect(freeze_nodes.length).to eq(1)

      # The class node should have leading comments attached
      class_node = analysis.statements.first
      expect(class_node).to be_a(Prism::ClassNode)

      leading_comments = class_node.location.leading_comments
      leading_text = leading_comments.map(&:slice).join
      expect(leading_text).to include("actual documentation")
    end
  end
end
