# frozen_string_literal: true

RSpec.describe Prism::Merge::DebugLogger, :check_output do
  before do
    stub_env("PRISM_MERGE_DEBUG" => "true")
    # Stub enabled to return true for most tests
    allow(described_class).to receive(:enabled).and_return(true)
    # Reset logger instance
    described_class.instance_variable_set(:@logger, nil)
  end

  after do
    # Reset logger state after each test
    described_class.instance_variable_set(:@logger, nil)
  end

  it "prints debug output using logger when available" do
    out = capture(:stdout) do
      described_class.debug("hello world", foo: :bar)
    end

    expect(out).to match(/hello world/)
    expect(out).to match(/foo|:bar/)
  end

  it "falls back to puts when logger is not available" do
    # Temporarily stub logger_available? to return false
    allow(described_class).to receive(:logger_available?).and_return(false)

    out = capture(:stdout) do
      described_class.debug("fallback", baz: 1)
    end
    expect(out).to match(/fallback/)
    expect(out).to match(/baz|1/)
  end

  it "handles empty context hash" do
    out = capture(:stdout) do
      described_class.debug("no context")
    end

    expect(out).to match(/no context/)
    # Should not have context string
    expect(out).not_to match(/\{/)
  end

  it "handles empty context with puts fallback" do
    allow(described_class).to receive(:logger_available?).and_return(false)

    out = capture(:stdout) do
      described_class.debug("no context fallback")
    end

    expect(out).to match(/no context fallback/)
  end

  it "reuses existing logger instance" do
    # First call creates logger
    capture(:stdout) do
      described_class.debug("first call")
    end

    logger_after_first = described_class.instance_variable_get(:@logger)
    expect(logger_after_first).not_to be_nil

    # Second call reuses logger
    capture(:stdout) do
      described_class.debug("second call")
    end

    logger_after_second = described_class.instance_variable_get(:@logger)
    expect(logger_after_second).to eq(logger_after_first)
  end

  it "does nothing when disabled" do
    allow(described_class).to receive(:enabled).and_return(false)

    out = capture(:stdout) do
      described_class.debug("should not appear")
    end

    expect(out).to be_empty
  end
end
