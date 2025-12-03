# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Branch Coverage" do
  describe "ConflictResolver edge cases" do
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

    context "with trailing blank line edge cases" do
      let(:fixture_dir) { File.expand_path("../../support/fixtures/smart_merge", __dir__) }
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

    context "with preference for template on signature match" do
      # signature_match_preference applies to TOP-LEVEL nodes with matching signatures.
      # For constants/variables: same name (value can differ)
      # For conditionals: same condition (body can differ)

      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "2.0.0"
          NAME = "updated-name"
          
          if ENV["DEBUG"]
            puts "Template debug"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          VERSION = "1.0.0"
          NAME = "original-name"
          CUSTOM = "custom-value"
          
          if ENV["DEBUG"]
            puts "Dest debug"
          end
        RUBY
      end

      it "uses template version when signature_match_preference is :template" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )

        result = merger.merge
        # Template versions should win for matching constants
        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include('NAME = "updated-name"')
        # Destination-only constant should still be included
        expect(result).to include('CUSTOM = "custom-value"')
        # Template version of conditional should win
        expect(result).to include('puts "Template debug"')
        expect(result).not_to include('puts "Dest debug"')
      end

      it "uses destination version when signature_match_preference is :destination (default)" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
          add_template_only_nodes: true,
        )

        result = merger.merge
        # Destination versions should win for matching constants
        expect(result).to include('VERSION = "1.0.0"')
        expect(result).to include('NAME = "original-name"')
        # Destination-only constant should be included
        expect(result).to include('CUSTOM = "custom-value"')
        # Destination version of conditional should win
        expect(result).to include('puts "Dest debug"')
        expect(result).not_to include('puts "Template debug"')
      end
    end

    context "with methods inside classes (documenting current behavior)" do
      # CURRENT LIMITATION: signature_match_preference does NOT apply to methods
      # inside classes. The entire class body is treated as destination content.
      # This documents the current behavior - may be addressed in future versions.

      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def method_a
              "template version a"
            end
            
            def method_b
              "template version b"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def method_a
              "destination version a"
            end
            
            def method_b
              "destination version b"
            end
            
            def custom_method
              "custom"
            end
          end
        RUBY
      end

      it "uses destination version regardless of signature_match_preference setting" do
        # With :template preference
        merger_template = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :template,
        )
        result_template = merger_template.merge

        # With :destination preference
        merger_dest = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          signature_match_preference: :destination,
        )
        result_dest = merger_dest.merge

        # Both produce the same result (destination version)
        expect(result_template).to eq(result_dest)
        expect(result_template).to include('"destination version a"')
        expect(result_template).to include('"destination version b"')
        expect(result_template).to include('"custom"')

        # Template versions are NOT used
        expect(result_template).not_to include('"template version a"')
        expect(result_template).not_to include('"template version b"')
      end
    end

    context "with add_template_only_nodes option" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def template_only_method
              "only in template"
            end
          
            def shared_method
              "shared"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def shared_method
              "shared"
            end
          
            def dest_only_method
              "only in dest"
            end
          end
        RUBY
      end

      it "includes template-only nodes when add_template_only_nodes is true" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: true,
        )

        result = merger.merge
        expect(result).to include("template_only_method")
        expect(result).to include("shared_method")
        expect(result).to include("dest_only_method")
      end

      it "excludes template-only nodes when add_template_only_nodes is false" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: false,
        )

        result = merger.merge
        expect(result).not_to include("template_only_method")
        expect(result).to include("shared_method")
        expect(result).to include("dest_only_method")
      end
    end

    context "with non-blank lines before nodes" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # Top level comment not attached to a node
          
          class MyClass
            # Comment attached to method
            def my_method
              "hello"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class MyClass
            def my_method
              "hello"
            end
          
            def custom
              "custom"
            end
          end
        RUBY
      end

      it "preserves unattached comments from template" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
        )

        result = merger.merge
        expect(result).to include("# Top level comment not attached to a node")
      end
    end
  end

  describe "FileAligner edge cases" do
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

  describe "SmartMerger with complex scenarios" do
    context "with mix of matched, template-only, and dest-only nodes" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class ComplexClass
            def shared_method_1
              "shared 1"
            end
            
            def template_only
              "template only"
            end
            
            def shared_method_2
              "shared 2"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          class ComplexClass
            def shared_method_1
              "shared 1 dest"
            end
            
            def dest_only
              "dest only"
            end
            
            def shared_method_2
              "shared 2 dest"
            end
          end
        RUBY
      end

      it "correctly merges with add_template_only_nodes: true" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: true,
        )

        result = merger.merge

        # Should have destination versions of shared methods
        expect(result).to include("shared 1 dest")
        expect(result).to include("shared 2 dest")

        # Should have both template-only and dest-only
        expect(result).to include("template_only")
        expect(result).to include("dest_only")
      end

      it "correctly merges with add_template_only_nodes: false" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
          add_template_only_nodes: false,
        )

        result = merger.merge

        # Should have destination versions of shared methods
        expect(result).to include("shared 1 dest")
        expect(result).to include("shared 2 dest")

        # Should NOT have template-only, but should have dest-only
        expect(result).not_to include("template_only")
        expect(result).to include("dest_only")
      end
    end

    context "with comments and blank lines around nodes" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # This is a class comment
          class MyClass
            # Method comment
            def method_a
              "a"
            end
          
          
            # Another method
            def method_b
              "b"
            end
          end
          
          
          # Trailing comment
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true
          
          # This is a class comment
          class MyClass
            def method_a
              "a custom"
            end
          
            def method_b
              "b custom"
            end
            
            def custom_method
              "custom"
            end
          end
        RUBY
      end

      it "preserves comments and handles blank lines correctly" do
        merger = Prism::Merge::SmartMerger.new(
          template_code,
          dest_code,
        )

        result = merger.merge

        expect(result).to include("# This is a class comment")
        expect(result).to include("method_a")
        expect(result).to include("method_b")
        expect(result).to include("custom_method")
        expect(result).to include("a custom")
        expect(result).to include("b custom")
      end
    end
  end
end
