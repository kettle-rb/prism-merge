# frozen_string_literal: true

require "prism/merge"

RSpec.describe "Frozen node edge cases" do
  describe "Question 1: Frozen template nodes and idempotency" do
    # Scenario:
    # 1. Template has a frozen node (freeze marker in leading comments)
    # 2. Destination doesn't have that node
    # 3. First merge: frozen node is added to destination
    # 4. Second merge: both have the frozen node - should match, not duplicate

    let(:template_with_frozen_method) do
      <<~RUBY
        # frozen_string_literal: true

        def regular_method
          "regular"
        end

        # prism-merge:freeze
        def frozen_method
          "this method is frozen in template"
        end
      RUBY
    end

    let(:destination_without_frozen_method) do
      <<~RUBY
        # frozen_string_literal: true

        def regular_method
          "regular in dest"
        end
      RUBY
    end

    it "adds frozen template node to destination on first merge" do
      merger = Prism::Merge::SmartMerger.new(
        template_with_frozen_method,
        destination_without_frozen_method,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "prism-merge",
      )

      result = merger.merge

      # Should have both methods
      expect(result).to include("def regular_method")
      expect(result).to include("def frozen_method")
      # Should include the freeze marker
      expect(result).to include("prism-merge:freeze")
    end

    it "is idempotent - second merge doesn't duplicate frozen nodes" do
      # First merge
      merger1 = Prism::Merge::SmartMerger.new(
        template_with_frozen_method,
        destination_without_frozen_method,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "prism-merge",
      )
      result1 = merger1.merge

      # Second merge: use result1 as new destination
      merger2 = Prism::Merge::SmartMerger.new(
        template_with_frozen_method,
        result1,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "prism-merge",
      )
      result2 = merger2.merge

      # Count occurrences
      frozen_method_count = result2.scan("def frozen_method").length
      freeze_marker_count = result2.scan("prism-merge:freeze").length

      expect(frozen_method_count).to eq(1),
        "Expected 1 frozen_method, found #{frozen_method_count}.\n" \
          "Result:\n#{result2}"

      expect(freeze_marker_count).to eq(1),
        "Expected 1 freeze marker, found #{freeze_marker_count}.\n" \
          "Result:\n#{result2}"

      # Results should be identical (idempotent)
      expect(result2).to eq(result1),
        "Merge should be idempotent!\n" \
          "First merge:\n#{result1}\n\n" \
          "Second merge:\n#{result2}"
    end

    it "frozen nodes match by content signature, not node identity" do
      # Both template and destination have the same frozen node
      template_analysis = Prism::Merge::FileAnalysis.new(
        template_with_frozen_method,
        freeze_token: "prism-merge",
      )

      # Simulate the result of first merge (destination now has the frozen method)
      destination_with_frozen = <<~RUBY
        # frozen_string_literal: true

        def regular_method
          "regular in dest"
        end

        # prism-merge:freeze
        def frozen_method
          "this method is frozen in template"
        end
      RUBY

      dest_analysis = Prism::Merge::FileAnalysis.new(
        destination_with_frozen,
        freeze_token: "prism-merge",
      )

      # Find frozen nodes
      template_frozen = template_analysis.statements.find { |n| n.is_a?(Ast::Merge::Freezable) }
      dest_frozen = dest_analysis.statements.find { |n| n.is_a?(Ast::Merge::Freezable) }

      expect(template_frozen).not_to be_nil, "Template should have a frozen node"
      expect(dest_frozen).not_to be_nil, "Destination should have a frozen node"

      # Both should have matching signatures (FreezeNode signature based on content)
      template_sig = template_analysis.generate_signature(template_frozen)
      dest_sig = dest_analysis.generate_signature(dest_frozen)

      expect(template_sig).to eq(dest_sig),
        "Frozen node signatures should match!\n" \
          "Template: #{template_sig.inspect}\n" \
          "Dest: #{dest_sig.inspect}"
    end
  end

  describe "Question 2: Ruby block with only comments inside" do
    # What happens when a Ruby block has ONLY comments inside?
    # Where do those comments get attached by Prism?

    let(:block_with_only_comments) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          # This is a comment
          # Another comment
          # prism-merge:freeze
          # Frozen content comment
          # prism-merge:unfreeze
        end
      RUBY
    end

    let(:block_with_only_freeze_comment) do
      <<~RUBY
        # frozen_string_literal: true

        def empty_method
          # prism-merge:freeze
        end
      RUBY
    end

    it "parses blocks with only comments" do
      result = Prism.parse(block_with_only_comments)
      Prism::Merge::FileAnalysis.attach_comments_safely!(result)
      expect(result.success?).to be true

      # The block should parse, but the body may be nil or have a StatementsNode
      program = result.value
      call_node = program.statements.body.find { |n| n.is_a?(Prism::CallNode) }
      expect(call_node).not_to be_nil

      # Check what's inside the block
      block = call_node.block
      expect(block).not_to be_nil

      # Document what Prism does with comment-only blocks
      puts "Block class: #{block.class}"
      puts "Block body: #{block.body.inspect}"
      puts "Block body nil?: #{block.body.nil?}"

      if block.body
        puts "Block body class: #{block.body.class}"
        puts "Block body children: #{block.body.body.inspect}" if block.body.respond_to?(:body)
      end
    end

    it "handles freeze markers in comment-only blocks" do
      analysis = Prism::Merge::FileAnalysis.new(
        block_with_only_comments,
        freeze_token: "prism-merge",
      )

      # The outer Gem::Specification.new should NOT be frozen
      # (freeze marker is inside, not in leading comments)
      spec_node = analysis.statements.find do |node|
        actual = node.respond_to?(:unwrap) ? node.unwrap : node
        actual.is_a?(Prism::CallNode) && actual.name == :new
      end

      expect(spec_node).not_to be_nil
      expect(spec_node).not_to be_a(Ast::Merge::Freezable),
        "Outer block should NOT be frozen - freeze marker is inside"
    end

    it "investigates where Prism attaches comments in empty blocks" do
      result = Prism.parse(block_with_only_freeze_comment)
      Prism::Merge::FileAnalysis.attach_comments_safely!(result)
      expect(result.success?).to be true

      # Find the method definition
      program = result.value
      method_node = program.statements.body.find { |n| n.is_a?(Prism::DefNode) }
      expect(method_node).not_to be_nil

      # Check the body
      puts "\n=== Method with only freeze comment ==="
      puts "Method body: #{method_node.body.inspect}"
      puts "Method body nil?: #{method_node.body.nil?}"

      # Check where comments are attached
      # In Prism, comments in an otherwise empty block might become:
      # 1. Part of the parent node's trailing comments
      # 2. Attached to a nil body somehow
      # 3. Lost entirely

      # Let's check the full comment list from the parse result
      puts "All comments in file: #{result.comments.map(&:slice).inspect}"

      # Check if comments are on the method node
      if method_node.location.respond_to?(:leading_comments)
        puts "Method leading comments: #{method_node.location.leading_comments.map(&:slice).inspect}"
      end
      if method_node.location.respond_to?(:trailing_comments)
        puts "Method trailing comments: #{method_node.location.trailing_comments.map(&:slice).inspect}"
      end
    end

    it "documents Prism comment attachment behavior for empty blocks" do
      # This test documents the actual behavior for future reference
      code = <<~RUBY
        def method_with_comment_body
          # prism-merge:freeze
          # frozen content
          # prism-merge:unfreeze
        end
      RUBY

      # Parse and attach comments to nodes (using JRuby-safe class method)
      result = Prism.parse(code)
      Prism::Merge::FileAnalysis.attach_comments_safely!(result)

      method_node = result.value.statements.body.first
      expect(method_node).to be_a(Prism::DefNode)

      # Document where the comments ended up
      puts "\n=== Comment attachment in empty method body ==="
      puts "Method body: #{method_node.body.inspect}"

      # If body is nil, comments might be orphaned or attached elsewhere
      if method_node.body.nil?
        puts "WARNING: Method body is nil - comments may not be attached to any statement"
        puts "This could affect freeze detection for empty blocks"
        puts "All comments in parse result: #{result.comments.map(&:slice).inspect}"
      else
        puts "Method body class: #{method_node.body.class}"
        if method_node.body.respond_to?(:body) && method_node.body.body
          method_node.body.body.each_with_index do |stmt, i|
            puts "Statement #{i}: #{stmt.class}"
            if stmt.location.respond_to?(:leading_comments)
              puts "  Leading comments: #{stmt.location.leading_comments.map(&:slice)}"
            end
          end
        end
      end
    end
  end
end
