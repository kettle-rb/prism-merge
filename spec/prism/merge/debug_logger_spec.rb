# frozen_string_literal: true

RSpec.describe Prism::Merge::DebugLogger, :check_output do
  before do
    stub_env("PRISM_MERGE_DEBUG" => "true")
    # reset internal enabled flag and logger
    described_class.instance_variable_set(:@enabled, true)
    described_class.instance_variable_set(:@logger, nil)
  end

  after do
    # Reset state after each test
    described_class.instance_variable_set(:@enabled, false)
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
end
