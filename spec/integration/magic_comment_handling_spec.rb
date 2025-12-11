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

  describe "freeze marker handling" do
    it "detects frozen nodes via freeze markers in leading comments" do
      content = <<~RUBY
        # frozen_string_literal: true
        
        # Regular comment before
        
        # prism-merge:freeze
        CONST = "value"
        
        # Regular comment after
        OTHER = "other"
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # All statements are regular Prism nodes (some may be wrapped as FrozenWrapper)
      expect(analysis.statements.length).to eq(2)

      # Helper to get the actual node (unwrap if needed)
      unwrap = ->(node) { node.respond_to?(:unwrap) ? node.unwrap : node }
      
      # Helper to check if node is a ConstantWriteNode with a specific name
      is_const = ->(node, name) {
        actual = unwrap.call(node)
        actual.is_a?(Prism::ConstantWriteNode) && actual.name == name
      }

      # First constant is frozen (has freeze marker in leading comments)
      const_node = analysis.statements.find { |s| is_const.call(s, :CONST) }
      expect(const_node).not_to be_nil
      expect(analysis.frozen_node?(const_node)).to be true

      # Second constant is not frozen
      other_node = analysis.statements.find { |s| is_const.call(s, :OTHER) }
      expect(other_node).not_to be_nil
      expect(analysis.frozen_node?(other_node)).to be false
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
          
          # steep:ignore
          def method_one
            # Comment inside method
            "one"
          end
        end
        # rubocop:enable Style/Documentation
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(content)

      # Should have one statement (ClassNode or FrozenWrapper around ClassNode)
      expect(analysis.statements.length).to eq(1)
      class_node = analysis.statements.first
      
      # The class contains a nested freeze marker, so it may be wrapped
      # Unwrap if needed to get the actual ClassNode
      actual_node = class_node.respond_to?(:unwrap) ? class_node.unwrap : class_node
      expect(actual_node).to be_a(Prism::ClassNode)

      # The class contains a nested freeze marker, so the whole class is frozen
      expect(analysis.frozen_node?(class_node)).to be true

      # Leading comments are attached to the class
      leading_comments = actual_node.location.leading_comments
      leading_text = leading_comments.map(&:slice).join
      expect(leading_text).to include("actual documentation")
    end
  end
end
