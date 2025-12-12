# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Frozen Node Detection" do
  describe "frozen_node? detection" do
    it "detects freeze marker in leading comments" do
      code = <<~RUBY
        # prism-merge:freeze
        def frozen_method
          "frozen"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      expect(analysis.frozen_node?(method_node)).to be true
    end

    it "does NOT freeze outer node when freeze marker is nested inside" do
      # A freeze marker INSIDE a block applies to the nested statement it precedes,
      # not to the enclosing block. This is the correct Ruby semantics.
      code = <<~RUBY
        Gem::Specification.new do |spec|
          # prism-merge:freeze
          spec.name = "example"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code)
      call_node = analysis.statements.first

      # The outer block should NOT be frozen - the freeze marker applies to the nested spec.name assignment
      expect(analysis.frozen_node?(call_node)).to be false
    end

    it "returns false for nodes without freeze marker" do
      code = <<~RUBY
        def regular_method
          "not frozen"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code)
      method_node = analysis.statements.first

      expect(analysis.frozen_node?(method_node)).to be false
    end

    it "uses custom freeze token" do
      code = <<~RUBY
        # kettle-dev:freeze
        CONST = "value"
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code, freeze_token: "kettle-dev")

      expect(analysis.frozen_node?(analysis.statements.first)).to be true
    end

    it "returns false when freeze_token is nil" do
      code = <<~RUBY
        # prism-merge:freeze
        def method
          "test"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code, freeze_token: nil)

      expect(analysis.frozen_node?(analysis.statements.first)).to be false
    end
  end

  describe "frozen_nodes collection" do
    it "returns only nodes with freeze markers" do
      code = <<~RUBY
        def method_a
          "a"
        end

        # prism-merge:freeze
        def frozen_method
          "frozen"
        end

        def method_b
          "b"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code)

      expect(analysis.frozen_nodes.size).to eq(1)
      expect(analysis.frozen_nodes.first.name).to eq(:frozen_method)
    end
  end

  describe "unfreeze markers are ignored" do
    it "does not affect frozen status" do
      code = <<~RUBY
        # prism-merge:freeze
        def method_one
          "frozen"
        end
        # prism-merge:unfreeze

        def method_two
          "not frozen"
        end
      RUBY

      analysis = Prism::Merge::FileAnalysis.new(code)
      method_one = analysis.statements.find { |s| s.name == :method_one }
      method_two = analysis.statements.find { |s| s.name == :method_two }

      expect(analysis.frozen_node?(method_one)).to be true
      expect(analysis.frozen_node?(method_two)).to be false
    end
  end

  describe "merge behavior" do
    it "preserves frozen destination nodes" do
      template = <<~RUBY
        def method
          "template"
        end
      RUBY

      dest = <<~RUBY
        # prism-merge:freeze
        def method
          "destination"
        end
      RUBY

      merger = Prism::Merge::SmartMerger.new(template, dest, freeze_token: "prism-merge")
      result = merger.merge

      expect(result).to include('"destination"')
      expect(result).not_to include('"template"')
    end

    it "preserves frozen nodes even with template preference" do
      template = <<~RUBY
        def method
          "template"
        end
      RUBY

      dest = <<~RUBY
        # prism-merge:freeze
        def method
          "destination"
        end
      RUBY

      merger = Prism::Merge::SmartMerger.new(
        template,
        dest,
        preference: :template,
        freeze_token: "prism-merge",
      )
      result = merger.merge

      expect(result).to include('"destination"')
    end
  end
end
