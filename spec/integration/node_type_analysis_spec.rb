# frozen_string_literal: true

require "spec_helper"

# Tests for various Ruby node types and constructs
RSpec.describe "Node Type Analysis" do
  describe "with uncommon node types" do
    let(:code) do
      <<~RUBY
        # frozen_string_literal: true

        # Defined check
        defined?(Object)

        # Alias
        alias new_name old_name

        # Undef
        undef some_method

        # BEGIN/END blocks
        BEGIN { puts "begin" }
        END { puts "end" }

        # Retry in rescue
        begin
          risky
        rescue
          retry
        end

        # Redo in loop
        loop do
          redo if condition
        end

        # Flip-flop
        (1..10).each { |i| puts i if i==2..i==5 }
      RUBY
    end

    it "handles uncommon Ruby node types" do
      analysis = Prism::Merge::FileAnalysis.new(code)
      expect(analysis.statements).not_to be_empty

      # Should parse without errors
      expect(analysis.parse_result).not_to be_nil
    end
  end

  describe "with various operators" do
    let(:code) do
      <<~RUBY
        # frozen_string_literal: true

        # Safe navigation
        obj&.method

        # Splat and double splat
        array = [1, *other, 2]
        hash = {a: 1, **other_hash}

        # Pattern matching
        case value
        in Integer
          "int"
        in String
          "str"
        end

        # Numbered parameters
        [1, 2, 3].map { _1 * 2 }

        # Endless method
        def double(x) = x * 2

        # Rightward assignment
        expr => result
      RUBY
    end

    it "handles modern Ruby operators and syntax" do
      analysis = Prism::Merge::FileAnalysis.new(code)
      expect(analysis.statements).not_to be_empty
      expect(analysis.parse_result).not_to be_nil
    end
  end

  describe "with deeply nested structures" do
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

  describe "with various Ruby constructs" do
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
