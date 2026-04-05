# frozen_string_literal: true

require "spec_helper"

# Integration tests for BlockDirective unification (Phases 2-4).
# Verifies that standalone freeze/unfreeze instruction blocks are NOT misidentified
# as freezing subsequent code nodes, and that nocov blocks are correctly promoted.
RSpec.describe "BlockDirective integration" do
  let(:freeze_token) { "kettle-jem" }

  describe "standalone freeze/unfreeze block at top of file" do
    let(:dest_source) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-jem:freeze
        # Custom header to preserve
        # kettle-jem:unfreeze

        require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?

        desc "hello"
        task :hello do
          puts "hello"
        end
      RUBY
    end

    it "does NOT mark the first code node as frozen (not wrapped in FrozenWrapper)" do
      analysis = Prism::Merge::FileAnalysis.new(dest_source, freeze_token: freeze_token)
      stmts = analysis.statements

      freeze_node = stmts.find { |s| s.is_a?(Prism::Merge::FreezeNode) }
      require_node = stmts.find { |s| s.is_a?(Prism::IfNode) }

      expect(freeze_node).not_to be_nil, "expected a FreezeNode to be promoted"
      expect(require_node).not_to be_nil, "expected IfNode to remain in statements"
      # The IfNode must NOT be wrapped in FrozenWrapper (it should not be frozen)
      expect(require_node).to be_a(Prism::IfNode)
      expect(require_node).not_to be_a(Ast::Merge::Freezable)
    end

    it "promotes the balanced freeze/unfreeze block to a FreezeNode" do
      analysis = Prism::Merge::FileAnalysis.new(dest_source, freeze_token: freeze_token)
      freeze_nodes = analysis.statements.select { |s| s.is_a?(Prism::Merge::FreezeNode) }
      expect(freeze_nodes.size).to eq(1)
    end
  end

  describe "nocov block wrapping a node" do
    let(:source_with_nocov) do
      <<~RUBY
        code = 1
        # :nocov:
        def unreachable_branch
          raise "should not happen"
        end
        # :nocov:
        other = 2
      RUBY
    end

    it "promotes the nocov block to a NocovNode" do
      analysis = Prism::Merge::FileAnalysis.new(source_with_nocov)
      nocov_nodes = analysis.statements.select { |s| s.is_a?(Prism::Merge::NocovNode) }
      expect(nocov_nodes.size).to eq(1)
    end

    it "removes inner nodes from top-level statements" do
      analysis = Prism::Merge::FileAnalysis.new(source_with_nocov)
      method_at_top = analysis.statements.find { |s| s.is_a?(Prism::DefNode) }
      expect(method_at_top).to be_nil
    end

    it "contains the wrapped def node as a child" do
      analysis = Prism::Merge::FileAnalysis.new(source_with_nocov)
      nocov_node = analysis.statements.find { |s| s.is_a?(Prism::Merge::NocovNode) }
      inner_def = nocov_node.children.find { |c| c.is_a?(Prism::DefNode) }
      expect(inner_def).not_to be_nil
    end
  end

  describe "freeze block wrapping a constant" do
    let(:source_with_freeze) do
      <<~RUBY
        # frozen_string_literal: true

        # kettle-jem:freeze
        CUSTOM_CONFIG = { key: "value" }
        # kettle-jem:unfreeze

        def normal; end
      RUBY
    end

    it "promotes the freeze block to a FreezeNode" do
      analysis = Prism::Merge::FileAnalysis.new(source_with_freeze, freeze_token: freeze_token)
      freeze_nodes = analysis.statements.select { |s| s.is_a?(Prism::Merge::FreezeNode) }
      expect(freeze_nodes.size).to eq(1)
    end

    it "contains the constant as a child of the FreezeNode" do
      analysis = Prism::Merge::FileAnalysis.new(source_with_freeze, freeze_token: freeze_token)
      freeze_node = analysis.statements.find { |s| s.is_a?(Prism::Merge::FreezeNode) }
      expect(freeze_node.nodes).not_to be_empty
    end
  end

  describe "SmartMerger: NocovNode follows file preference" do
    let(:template_source) do
      <<~RUBY
        # frozen_string_literal: true

        # :nocov:
        def unreachable
          raise "oops"
        end
        # :nocov:

        def normal; end
      RUBY
    end

    let(:dest_source) do
      <<~RUBY
        # frozen_string_literal: true

        # :nocov:
        def unreachable
          raise "oops"
        end
        # :nocov:

        def normal; end
      RUBY
    end

    it "NocovNode has nil merge_policy (follows file preference)" do
      analysis = Prism::Merge::FileAnalysis.new(dest_source)
      nocov = analysis.statements.find { |s| s.is_a?(Prism::Merge::NocovNode) }
      expect(nocov).not_to be_nil
      expect(nocov.merge_policy).to be_nil
    end

    it "merges correctly with :template preference" do
      result = Prism::Merge::SmartMerger.new(
        template_source,
        dest_source,
        preference: :template,
      ).merge_result

      expect(result.to_s).to include("# :nocov:")
      expect(result.to_s).to include("def unreachable")
      expect(result.to_s).to include("def normal")
    end
  end
end
