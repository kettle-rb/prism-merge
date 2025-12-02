# frozen_string_literal: true

RSpec.describe Prism::Merge::Version do
  before do
    stub_const("Prism::Merge::Version::VERSION", "12.34.56.pre-78")
  end

  it_behaves_like "a Version module", described_class

  it "is greater than 0.1.0" do
    expect(Gem::Version.new(described_class) > Gem::Version.new("0.1.0")).to(be(true))
  end

  it "major version is an integer" do
    expect(described_class.major).to(eq(12))
  end

  it "minor version is an integer" do
    expect(described_class.minor).to(eq(34))
  end

  it "patch version is an integer" do
    expect(described_class.patch).to(eq(56))
  end

  it "pre version is an string" do
    expect(described_class.pre).to(eq("pre-78"))
  end

  it "returns a Hash" do
    expect(described_class.to_h).to(eq(major: 12, minor: 34, patch: 56, pre: "pre-78"))
  end

  it "returns an Array" do
    expect(described_class.to_a).to(eq([12, 34, 56, "pre-78"]))
  end
end
