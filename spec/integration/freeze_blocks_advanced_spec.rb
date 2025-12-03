# frozen_string_literal: true

require "spec_helper"

# Advanced freeze block scenarios specifically targeting uncovered branches
RSpec.describe "Advanced Freeze Block Coverage" do
  describe "freeze block detection and handling" do
    context "when template has kettle-dev:freeze markers" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          class MyClass
            # kettle-dev:freeze
            FROZEN_CONST = "template"
            
            def frozen_method
              "template"
            end
            # kettle-dev:unfreeze

            def normal_method
              "template"
            end
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          class MyClass
            # kettle-dev:freeze
            FROZEN_CONST = "dest"
            EXTRA_CONST = "dest only"
            
            def frozen_method
              "dest - customized"
            end
            # kettle-dev:unfreeze

            def normal_method
              "dest"
            end
            
            def custom_method
              "custom"
            end
          end
        RUBY
      end

      it "detects and preserves destination freeze blocks" do
        template_analysis = Prism::Merge::FileAnalysis.new(template_code)
        dest_analysis = Prism::Merge::FileAnalysis.new(dest_code)

        aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
        boundaries = aligner.align

        resolver = Prism::Merge::ConflictResolver.new(template_analysis, dest_analysis)
        result = Prism::Merge::MergeResult.new

        boundaries.each do |boundary|
          resolver.resolve(boundary, result)
        end

        output = result.to_s
        expect(output).to include("kettle-dev:freeze")
        expect(output).to include('FROZEN_CONST = "dest"')
        expect(output).to include('EXTRA_CONST = "dest only"')
        expect(output).to include("dest - customized")
        expect(output).to include("custom_method")
      end
    end

    context "with freeze block as first content in file" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          VERSION = "1.0.0"
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          VERSION = "2.0.0"
          AUTHOR = "Custom"
          # kettle-dev:unfreeze
        RUBY
      end

      it "handles freeze block at file start" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('VERSION = "2.0.0"')
        expect(result).to include('AUTHOR = "Custom"')
      end
    end

    context "with freeze block as last content in file" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          def method
            "method"
          end

          # kettle-dev:freeze
          FINAL = "template"
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          def method
            "method"
          end

          # kettle-dev:freeze
          FINAL = "dest"
          EXTRA = "dest"
          # kettle-dev:unfreeze
        RUBY
      end

      it "handles freeze block at file end" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('FINAL = "dest"')
        expect(result).to include('EXTRA = "dest"')
      end
    end

    context "with freeze block containing multi-line constructs" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          CONFIG = {
            key: "template"
          }
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          CONFIG = {
            key: "dest",
            extra: "custom"
          }
          # kettle-dev:unfreeze
        RUBY
      end

      it "preserves multi-line frozen constructs from destination" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('key: "dest"')
        expect(result).to include('extra: "custom"')
      end
    end

    context "with unmatched freeze/unfreeze markers" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          CONST = "value"
          # Missing unfreeze marker
          
          def method
            "method"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          CONST = "dest"
          
          def method
            "dest"
          end
        RUBY
      end

      it "handles unmatched freeze markers gracefully" do
        # Should not crash with unmatched markers
        expect {
          merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
          merger.merge
        }.not_to raise_error
      end
    end

    context "with only freeze marker, no unfreeze" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          A = "a"
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          A = "dest_a"
          B = "dest_b"
        RUBY
      end

      it "handles freeze without unfreeze" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        # Should still handle the freeze block
        expect(result).to include("kettle-dev:freeze")
      end
    end

    context "with empty freeze block" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          # kettle-dev:unfreeze
          
          def method
            "method"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          CONST = "added in dest"
          # kettle-dev:unfreeze
          
          def method
            "method"
          end
        RUBY
      end

      it "handles empty freeze block in template" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('CONST = "added in dest"')
      end
    end
  end

  describe "freeze block with various content types" do
    context "with class definitions inside freeze block" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          class FrozenClass
            def method
              "template"
            end
          end
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          class FrozenClass
            def method
              "dest - custom"
            end
            
            def extra_method
              "extra"
            end
          end
          # kettle-dev:unfreeze
        RUBY
      end

      it "preserves destination class definitions in freeze block" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include("dest - custom")
        expect(result).to include("extra_method")
      end
    end

    context "with module definitions inside freeze block" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          module FrozenModule
            VERSION = "1.0"
          end
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          module FrozenModule
            VERSION = "2.0"
            CUSTOM = "custom"
          end
          # kettle-dev:unfreeze
        RUBY
      end

      it "preserves destination module definitions in freeze block" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('VERSION = "2.0"')
        expect(result).to include('CUSTOM = "custom"')
      end
    end

    context "with method calls inside freeze block" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          require "template_lib"
          include TemplateModule
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          require "dest_lib"
          require "extra_lib"
          include DestModule
          # kettle-dev:unfreeze
        RUBY
      end

      it "preserves destination method calls in freeze block" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('require "dest_lib"')
        expect(result).to include('require "extra_lib"')
        expect(result).to include("include DestModule")
        expect(result).not_to include("TemplateModule")
      end
    end
  end

  describe "multiple freeze blocks in same file" do
    context "with non-overlapping freeze blocks" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          FIRST = "template_1"
          # kettle-dev:unfreeze

          def middle_method
            "template"
          end

          # kettle-dev:freeze
          SECOND = "template_2"
          # kettle-dev:unfreeze
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          FIRST = "dest_1"
          FIRST_EXTRA = "dest"
          # kettle-dev:unfreeze

          def middle_method
            "dest"
          end

          # kettle-dev:freeze
          SECOND = "dest_2"
          SECOND_EXTRA = "dest"
          # kettle-dev:unfreeze
        RUBY
      end

      it "handles multiple separate freeze blocks" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('FIRST = "dest_1"')
        expect(result).to include('FIRST_EXTRA = "dest"')
        expect(result).to include('SECOND = "dest_2"')
        expect(result).to include('SECOND_EXTRA = "dest"')
      end
    end

    context "with adjacent freeze blocks" do
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
          # kettle-dev:unfreeze
          # kettle-dev:freeze
          SECOND = "dest"
          # kettle-dev:unfreeze
        RUBY
      end

      it "handles adjacent freeze blocks correctly" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include('FIRST = "dest"')
        expect(result).to include('SECOND = "dest"')
        # Should have freeze/unfreeze markers (count may vary based on merging logic)
        expect(result).to include("kettle-dev:freeze")
        expect(result).to include("kettle-dev:unfreeze")
      end
    end
  end

  describe "freeze blocks with complex surrounding context" do
    context "with freeze block between matching methods" do
      let(:template_code) do
        <<~RUBY
          # frozen_string_literal: true

          def before_method
            "template"
          end

          # kettle-dev:freeze
          FROZEN = "template"
          # kettle-dev:unfreeze

          def after_method
            "template"
          end
        RUBY
      end

      let(:dest_code) do
        <<~RUBY
          # frozen_string_literal: true

          def before_method
            "template"
          end

          # kettle-dev:freeze
          FROZEN = "dest"
          EXTRA_FROZEN = "dest"
          # kettle-dev:unfreeze

          def after_method
            "template"
          end
          
          def custom_method
            "custom"
          end
        RUBY
      end

      it "correctly handles freeze block between matched methods" do
        merger = Prism::Merge::SmartMerger.new(template_code, dest_code)
        result = merger.merge

        expect(result).to include("before_method")
        expect(result).to include('FROZEN = "dest"')
        expect(result).to include('EXTRA_FROZEN = "dest"')
        expect(result).to include("after_method")
        expect(result).to include("custom_method")
      end
    end
  end
end
