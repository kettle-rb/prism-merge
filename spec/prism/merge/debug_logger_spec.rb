# frozen_string_literal: true

RSpec.describe Prism::Merge::DebugLogger, :check_output do
  before do
    stub_env("PRISM_MERGE_DEBUG" => "true")
    # Stub enabled? to return true for most tests
    allow(described_class).to receive(:enabled?).and_return(true)
  end

  describe ".enabled?" do
    it "returns true when PRISM_MERGE_DEBUG is '1'" do
      allow(described_class).to receive(:enabled?).and_call_original
      stub_env("PRISM_MERGE_DEBUG" => "1")
      expect(described_class.enabled?).to be true
    end

    it "returns true when PRISM_MERGE_DEBUG is 'true'" do
      allow(described_class).to receive(:enabled?).and_call_original
      stub_env("PRISM_MERGE_DEBUG" => "true")
      expect(described_class.enabled?).to be true
    end

    it "returns false when PRISM_MERGE_DEBUG is not set" do
      allow(described_class).to receive(:enabled?).and_call_original
      stub_env("PRISM_MERGE_DEBUG" => nil)
      expect(described_class.enabled?).to be false
    end
  end

  describe ".debug" do
    it "prints debug output to stderr with context" do
      out = capture(:stderr) do
        described_class.debug("hello world", foo: :bar)
      end

      expect(out).to match(/hello world/)
      expect(out).to match(/foo.*:bar/)
    end

    it "handles empty context hash" do
      out = capture(:stderr) do
        described_class.debug("no context")
      end

      expect(out).to match(/no context/)
      # Should not have context inspect output
      expect(out).not_to match(/\{\}/)
    end

    it "does nothing when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)

      out = capture(:stderr) do
        described_class.debug("should not appear")
      end

      expect(out).to be_empty
    end
  end

  describe ".info" do
    it "prints info message to stderr" do
      out = capture(:stderr) do
        described_class.info("info message")
      end

      expect(out).to match(/INFO/)
      expect(out).to match(/info message/)
    end

    it "does nothing when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)

      out = capture(:stderr) do
        described_class.info("should not appear")
      end

      expect(out).to be_empty
    end
  end

  describe ".warning" do
    it "prints warning message to stderr even when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)

      out = capture(:stderr) do
        described_class.warning("warning message")
      end

      expect(out).to match(/WARNING/)
      expect(out).to match(/warning message/)
    end
  end

  describe ".time" do
    it "times a block and logs duration when enabled" do
      out = capture(:stderr) do
        result = described_class.time("test operation") { 42 }
        expect(result).to eq(42)
      end

      expect(out).to match(/Starting: test operation/)
      expect(out).to match(/Completed: test operation/)
      expect(out).to match(/real_ms/)
    end

    it "returns block result without logging when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)

      out = capture(:stderr) do
        result = described_class.time("test operation") { 42 }
        expect(result).to eq(42)
      end

      expect(out).to be_empty
    end

    it "warns and returns block result when benchmark is unavailable" do
      stub_const("Prism::Merge::DebugLogger::BENCHMARK_AVAILABLE", false)

      out = capture(:stderr) do
        result = described_class.time("test operation") { 42 }
        expect(result).to eq(42)
      end

      expect(out).to match(/WARNING/)
      expect(out).to match(/Benchmark gem not available/)
      expect(out).to match(/test operation/)
      expect(out).not_to match(/real_ms/)
    end
  end

  describe ".log_node" do
    it "logs node information when enabled" do
      node = double("Node", class: "TestNode", location: double(start_line: 1))
      allow(node).to receive(:respond_to?).with(:location).and_return(true)

      out = capture(:stderr) do
        described_class.log_node(node, label: "TestLabel")
      end

      expect(out).to match(/TestLabel/)
    end

    it "does nothing when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)

      out = capture(:stderr) do
        described_class.log_node("anything", label: "Test")
      end

      expect(out).to be_empty
    end
  end
end
