# frozen_string_literal: true

require "spec_helper"

RSpec.describe Prism::Merge::RubyDocSurfaceAnalyzer do
  describe "#discover_doc_comment_surfaces" do
    it "discovers Ruby doc-comment surfaces from Prism-owned leading comments" do
      analysis = Prism::Merge::FileAnalysis.new(<<~'RUBY')
        # Greets the world.
        #
        # @example
        #   greet
        #   greet("team")
        def greet(name = "world")
          puts "Hello, #{name}"
        end
      RUBY

      surface = described_class.new(analysis).discover_doc_comment_surfaces.first

      expect(surface.surface_kind).to eq(:ruby_doc_comment)
      expect(surface.effective_language).to eq(:yard)
      expect(surface.address).to eq("document[0] > ruby_doc_comment[greet]")
      expect(surface.span).to eq(1..5)
      expect(surface.metadata[:owner_signature]).to eq([:def, :greet, [:name]])
      expect(surface.metadata[:comment_prefix]).to eq("# ")
    end

    it "ignores magic-comment-only leading regions" do
      analysis = Prism::Merge::FileAnalysis.new(<<~'RUBY')
        # frozen_string_literal: true
        class Example
        end
      RUBY

      surfaces = described_class.new(analysis).discover_doc_comment_surfaces

      expect(surfaces).to eq([])
    end
  end

  describe "#discover_child_surfaces" do
    it "discovers @example child surfaces with hierarchical addresses" do
      analysis = Prism::Merge::FileAnalysis.new(<<~'RUBY')
        # Builds a greeting.
        #
        # @example [ruby]
        #   build_greeting("team")
        #   build_greeting("folks")
        #
        # @return [String]
        def build_greeting(name)
          "Hello, #{name}"
        end
      RUBY

      analyzer = described_class.new(analysis)
      doc_surface = analyzer.discover_doc_comment_surfaces.first
      example_surface = analyzer.discover_child_surfaces(doc_surface).first

      expect(example_surface.surface_kind).to eq(:yard_example_block)
      expect(example_surface.parent_address).to eq(doc_surface.address)
      expect(example_surface.address).to eq("#{doc_surface.address} > yard_example[2]")
      expect(example_surface.declared_language).to eq(:ruby)
      expect(example_surface.effective_language).to eq(:ruby)
      expect(example_surface.span).to eq(4..6)
      expect(example_surface.metadata[:tag_line]).to eq(3)
      expect(example_surface.metadata.dig(:preserved_boundaries, :tag_header)).to eq("# @example [ruby]")
    end
  end
end
