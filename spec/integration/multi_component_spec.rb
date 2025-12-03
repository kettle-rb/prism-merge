# frozen_string_literal: true

require "spec_helper"

# Integration tests that test multiple components together
# These test the interaction between FileAnalysis, FileAligner, and ConflictResolver
RSpec.describe "Multi-component integration" do
  describe "FileAnalysis, FileAligner, and ConflictResolver" do
    context "with empty template range" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # Just a comment, no actual nodes
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class DestClass
            def method
              "dest"
            end
          end
        RUBY
      end

      it "handles nil/empty template range gracefully" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        resolver = Prism::Merge::ConflictResolver.new(template_analysis, dest_analysis)
        result = Prism::Merge::MergeResult.new

        boundaries.each do |boundary|
          resolver.resolve(boundary, result)
        end

        expect(result.to_s).to include("DestClass")
      end
    end

    context "with no common anchors" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class TemplateClass
            def template_method
              "template"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class DestinationClass
            def dest_method
              "dest"
            end
          end
        RUBY
      end

      it "creates boundaries for completely different files" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        expect(boundaries).not_to be_empty
        expect(boundaries.first.template_range).not_to be_nil
        expect(boundaries.first.dest_range).not_to be_nil
      end
    end

    context "with anchors at file boundaries" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          
          class MyClass
            def method1
              "one"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          
          class MyClass
            def method1
              "one"
            end
          
            def custom
              "custom"
            end
          end
        RUBY
      end

      it "handles anchors at beginning and end of files" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
        )

        result = merger.merge
        expect(result).to include('VERSION = "1.0.0"')
        expect(result).to include("method1")
        expect(result).to include("custom")
      end
    end

    context "with signature match anchors" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "2.0.0"
          if ENV["DEBUG"]
            puts "debug"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          if ENV["DEBUG"]
            puts "debug"
          end
        RUBY
      end

      it "creates signature_match anchor type" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)
        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        aligner.align

        # Should have signature match anchors
        sig_match_anchors = aligner.anchors.select { |a| a.match_type == :signature_match }
        expect(sig_match_anchors).not_to be_empty
      end
    end
  end

  describe "FileAnalysis edge cases" do
    context "with deeply nested structures" do
      let(:code) do
        <<~RUBY
          # frozen_string_literal: true
          
          module Outer
            module Inner
              class DeepClass
                def deep_method
                  if condition
                    case value
                    when :a
                      "a"
                    when :b
                      "b"
                    else
                      "other"
                    end
                  end
                end
              end
            end
          end
        RUBY
      end

      it "analyzes deeply nested structures" do
        analysis = Prism::Merge::FileAnalysis.new(code)
        expect(analysis.statements).not_to be_empty
        expect(analysis.nodes_with_comments).not_to be_empty
      end
    end

    context "with various Ruby constructs" do
      let(:code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # Constants
          CONSTANT = 42
          
          # Class with inheritance
          class Child < Parent
            include Mixin
            extend Extension
            
            attr_reader :name
            attr_accessor :value
            
            # Class method
            def self.class_method
              "class"
            end
            
            # Instance method
            def instance_method(arg, keyword: nil)
              @value = arg
            end
            
            # Private methods
            private
            
            def private_method
              "private"
            end
          end
          
          # Module
          module MyModule
            def module_method
              "module"
            end
          end
          
          # Lambda and Proc
          my_lambda = ->(x) { x * 2 }
          my_proc = proc { |x| x * 2 }
          
          # Block
          [1, 2, 3].each do |n|
            puts n
          end
        RUBY
      end

      it "handles various Ruby constructs" do
        analysis = Prism::Merge::FileAnalysis.new(code)
        expect(analysis.statements.size).to be > 5
        expect(analysis.nodes_with_comments.size).to be > 3
      end
    end
  end

  describe "Trailing blank lines in ConflictResolver" do
    let(:fixture_dir) { File.expand_path("../support/fixtures/smart_merge", __dir__) }
    let(:template_path) { File.join(fixture_dir, "trailing_blanks.template.rb") }
    let(:dest_path) { File.join(fixture_dir, "trailing_blanks.destination.rb") }

    it "correctly handles trailing blank lines between nodes" do
      template_code = File.read(template_path)
      dest_code = File.read(dest_path)

      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        add_template_only_nodes: true,
      )

      result = merger.merge
      expect(result).to include("method_with_trailing_blanks")
      expect(result).to include("another_method")
      expect(result).to include("custom_method")
    end
  end

  describe "Freeze block handling" do
    context "with multiple consecutive freeze blocks" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # kettle-dev:freeze
          FIRST = "template"
          # kettle-dev:unfreeze
          
          # kettle-dev:freeze
          SECOND = "template"
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # kettle-dev:freeze
          FIRST = "dest"
          EXTRA = "dest extra"
          # kettle-dev:unfreeze
          
          # kettle-dev:freeze
          SECOND = "dest"
          # kettle-dev:unfreeze
        RUBY
      end

      it "preserves all destination freeze blocks" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
        )

        result = merger.merge
        expect(result).to include('FIRST = "dest"')
        expect(result).to include('EXTRA = "dest extra"')
        expect(result).to include('SECOND = "dest"')
        expect(result).not_to include('FIRST = "template"')
        expect(result).not_to include('SECOND = "template"')
      end
    end
  end
end
