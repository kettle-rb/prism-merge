# frozen_string_literal: true

require "spec_helper"

# Tests for template preference in signature matching
RSpec.describe "Template Preference Signature Matching" do
  describe "when using template preference for matching signatures" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a(arg)
          "template version"
        end

        def method_b(x, y)
          "template b"
        end

        def method_c
          "template c"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def method_a(arg)
          "dest version with customization"
        end

        def method_b(x, y)
          "dest b with custom logic"
        end

        def method_c
          "dest c"
        end
      RUBY
    end

    it "uses template version when preference is :template" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :template,
      )
      result = merger.merge

      # Should use template versions
      expect(result).to include("template version")
      expect(result).to include("template b")
      expect(result).to include("template c")
      expect(result).not_to include("customization")
      expect(result).not_to include("custom logic")
    end
  end

  describe "with complex method signatures" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        def complex_method(required, optional = "default", *args, keyword: "value", **kwargs, &block)
          "template implementation"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        def complex_method(required, optional = "default", *args, keyword: "value", **kwargs, &block)
          "dest implementation with custom behavior"
        end
      RUBY
    end

    it "matches complex signatures and respects template preference" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :template,
      )
      result = merger.merge

      expect(result).to include("template implementation")
      expect(result).not_to include("custom behavior")
    end
  end

  describe "with class methods" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        class MyClass
          def self.class_method
            "template class method"
          end

          def instance_method
            "template instance"
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        class MyClass
          def self.class_method
            "dest class method"
          end

          def instance_method
            "dest instance"
          end
        end
      RUBY
    end

    it "uses template preference for both class and instance methods" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :template,
      )
      result = merger.merge

      expect(result).to include("template class method")
      expect(result).to include("template instance")
    end
  end

  describe "with assignment statements" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        CONST_A = "template_a"
        CONST_B = {key: "template"}
        @instance_var = "template"
        @@class_var = "template"
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        CONST_A = "dest_a"
        CONST_B = {key: "dest", extra: "value"}
        @instance_var = "dest"
        @@class_var = "dest"
      RUBY
    end

    it "uses template preference for assignments" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :template,
      )
      result = merger.merge

      expect(result).to include('CONST_A = "template_a"')
      expect(result).to include('{key: "template"}')
    end
  end
end
