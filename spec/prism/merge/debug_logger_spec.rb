# frozen_string_literal: true

RSpec.describe Prism::Merge::DebugLogger do
  # Use the shared examples to validate base DebugLogger integration
  it_behaves_like "Ast::Merge::DebugLogger" do
    let(:described_logger) { described_class }
    let(:env_var_name) { "PRISM_MERGE_DEBUG" }
    let(:log_prefix) { "[Prism::Merge]" }
  end

  describe "Prism-specific extract_node_info override" do
    before do
      stub_env("PRISM_MERGE_DEBUG" => "1")
    end

    it "handles FreezeNode" do
      # Create a mock FreezeNode-like object
      freeze_node_class = Class.new do
        attr_reader :start_line, :end_line

        def initialize(start_line:, end_line:)
          @start_line = start_line
          @end_line = end_line
        end
      end

      # Define FreezeNode constant temporarily
      stub_const("Prism::Merge::FreezeNode", freeze_node_class)
      node = freeze_node_class.new(start_line: 1, end_line: 5)

      info = described_class.extract_node_info(node)

      expect(info[:type]).to eq("FreezeNode")
      expect(info[:lines]).to eq("1..5")
    end

    it "delegates to base implementation for non-FreezeNode types" do
      node = Object.new

      info = described_class.extract_node_info(node)

      expect(info[:type]).to eq("Object")
    end
  end
end
