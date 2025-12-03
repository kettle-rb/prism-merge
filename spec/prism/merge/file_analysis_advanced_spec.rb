# frozen_string_literal: true

RSpec.describe Prism::Merge::FileAnalysis do
  describe "error handling and edge cases" do
    context "with invalid Ruby code" do
      it "marks analysis as invalid" do
        invalid_content = <<~RUBY
          def broken(
            # missing closing parenthesis
        RUBY

        analysis = described_class.new(invalid_content)

        expect(analysis.valid?).to be false
        expect(analysis.statements).to be_empty
      end

      it "handles syntax errors gracefully in freeze block detection" do
        invalid_content = <<~RUBY
          # kettle-dev:freeze
          def broken(
          # kettle-dev:unfreeze
        RUBY

        analysis = described_class.new(invalid_content)

        # Should still detect freeze blocks even with invalid syntax
        expect(analysis.freeze_blocks.length).to eq(1)
      end
    end

    context "with custom signature generator" do
      it "uses custom signature generator when provided" do
        content = <<~RUBY
          def custom_method
            puts "test"
          end
        RUBY

        custom_generator = ->(node) { [:custom, node.class.name] }
        analysis = described_class.new(content, signature_generator: custom_generator)

        signature = analysis.signature_at(0)
        expect(signature).to eq([:custom, "Prism::DefNode"])
      end

      it "falls back to default signature when custom generator returns nil" do
        content = <<~RUBY
          def fallback_method
            puts "test"
          end
        RUBY

        custom_generator = ->(_node) { nil }
        analysis = described_class.new(content, signature_generator: custom_generator)

        # Should use default signature
        signature = analysis.signature_at(0)
        expect(signature).to be_nil # custom returned nil
      end
    end

    context "with line_to_node_map" do
      it "returns empty map for invalid content" do
        invalid_content = "def broken("
        analysis = described_class.new(invalid_content)

        map = analysis.line_to_node_map
        expect(map).to be_a(Hash)
        expect(map).to be_empty
      end

      it "maps multiple nodes on same line" do
        content = "a = 1; b = 2; c = 3"
        analysis = described_class.new(content)

        map = analysis.line_to_node_map
        expect(map[1]).to be_an(Array)
        expect(map[1].length).to be >= 1
      end

      it "caches the map on subsequent calls" do
        content = "def hello; end"
        analysis = described_class.new(content)

        first_call = analysis.line_to_node_map
        second_call = analysis.line_to_node_map

        expect(first_call.object_id).to eq(second_call.object_id)
      end
    end

    context "with node_to_line_map" do
      it "returns empty map for invalid content" do
        invalid_content = "def broken("
        analysis = described_class.new(invalid_content)

        map = analysis.node_to_line_map
        expect(map).to be_a(Hash)
        expect(map).to be_empty
      end

      it "maps nodes to their line ranges" do
        content = <<~RUBY
          def multi_line_method
            puts "line 2"
            puts "line 3"
          end
        RUBY

        analysis = described_class.new(content)
        map = analysis.node_to_line_map

        expect(map).not_to be_empty
        node = analysis.statements.first
        expect(map[node]).to eq(1..4)
      end

      it "caches the map on subsequent calls" do
        content = "def hello; end"
        analysis = described_class.new(content)

        first_call = analysis.node_to_line_map
        second_call = analysis.node_to_line_map

        expect(first_call.object_id).to eq(second_call.object_id)
      end
    end

    context "with comment_map" do
      it "returns empty map for invalid content" do
        invalid_content = "def broken("
        analysis = described_class.new(invalid_content)

        map = analysis.comment_map
        expect(map).to be_a(Hash)
      end

      it "maps comments to their line numbers" do
        content = <<~RUBY
          # Comment on line 1
          # Comment on line 2
          def method # inline comment
            # Comment on line 4
            puts "test"
          end
        RUBY

        analysis = described_class.new(content)
        map = analysis.comment_map

        expect(map[1].length).to eq(1)
        expect(map[2].length).to eq(1)
        expect(map[3].length).to eq(1)
        expect(map[4].length).to eq(1)
      end

      it "caches the map on subsequent calls" do
        content = "# comment"
        analysis = described_class.new(content)

        first_call = analysis.comment_map
        second_call = analysis.comment_map

        expect(first_call.object_id).to eq(second_call.object_id)
      end
    end

    context "with freeze_block_at" do
      it "returns nil for lines outside freeze blocks" do
        content = <<~RUBY
          line 1
          # kettle-dev:freeze
          line 3
          # kettle-dev:unfreeze
          line 5
        RUBY

        analysis = described_class.new(content)

        expect(analysis.freeze_block_at(1)).to be_nil
        expect(analysis.freeze_block_at(5)).to be_nil
      end

      it "returns freeze block metadata for lines inside freeze blocks" do
        content = <<~RUBY
          line 1
          # kettle-dev:freeze
          line 3
          # kettle-dev:unfreeze
          line 5
        RUBY

        analysis = described_class.new(content)

        block = analysis.freeze_block_at(3)
        expect(block).not_to be_nil
        expect(block[:line_range].cover?(3)).to be true
      end
    end

    context "with line_at method" do
      it "returns nil for invalid line numbers" do
        content = "line 1\nline 2\n"
        analysis = described_class.new(content)

        expect(analysis.line_at(0)).to be_nil
        expect(analysis.line_at(-1)).to be_nil
        expect(analysis.line_at(99)).to be_nil
      end

      it "returns line content for valid line numbers" do
        content = "line 1\nline 2\nline 3\n"
        analysis = described_class.new(content)

        expect(analysis.line_at(1)).to eq("line 1\n")
        expect(analysis.line_at(2)).to eq("line 2\n")
        expect(analysis.line_at(3)).to eq("line 3\n")
      end
    end

    context "with default signature generation" do
      it "generates signature for nil node" do
        analysis = described_class.new("# empty")
        signature = analysis.send(:default_signature, nil)

        expect(signature).to eq([:nil])
      end

      it "generates signature for IfNode based on condition" do
        content = <<~RUBY
          if x > 5
            puts "greater"
          end
        RUBY

        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:IfNode)
        expect(signature[1]).to include("x > 5")
      end

      it "generates signature for UnlessNode based on condition" do
        content = <<~RUBY
          unless x > 5
            puts "less or equal"
          end
        RUBY

        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:UnlessNode)
        expect(signature[1]).to include("x > 5")
      end

      it "generates signature for ConstantWriteNode based on name" do
        content = "VERSION = '1.0.0'"
        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:ConstantWriteNode)
        expect(signature[1]).to eq("VERSION")
      end

      it "generates signature for CallNode with block" do
        content = <<~RUBY
          configure do |config|
            config.setting = true
          end
        RUBY

        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:CallNode)
        expect(signature[1]).to eq("configure")
      end

      it "generates signature for CallNode with arguments" do
        content = 'puts "hello", "world"'
        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:CallNode)
        expect(signature[1]).to eq("puts")
      end

      it "generates signature for DefNode" do
        content = <<~RUBY
          def method_name(param1, param2)
            puts "test"
          end
        RUBY

        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:DefNode)
        expect(signature[1]).to include("def method_name")
        expect(signature[1]).to include("param1, param2")
      end

      it "generates signature for ClassNode" do
        content = <<~RUBY
          class MyClass
            def method
            end
          end
        RUBY

        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:ClassNode)
        expect(signature[1]).to include("class MyClass")
      end

      it "generates signature for ModuleNode" do
        content = <<~RUBY
          module MyModule
            def method
            end
          end
        RUBY

        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:ModuleNode)
        expect(signature[1]).to include("module MyModule")
      end

      it "generates generic signature for other node types" do
        content = "42"
        analysis = described_class.new(content)
        node = analysis.statements.first

        signature = analysis.send(:default_signature, node)
        expect(signature[0]).to eq(:IntegerNode)
        expect(signature[1]).to eq("42")
      end
    end
  end
end
