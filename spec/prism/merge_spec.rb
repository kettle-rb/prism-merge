# frozen_string_literal: true

RSpec.describe Prism::Merge do
  it "does something useful" do
    expect(described_class).to be_a(Module)
  end

  describe ".register_backend!" do
    it "registers ruby with TreeHaver" do
      registrations = TreeHaver.registered_language(:ruby)

      expect(registrations).to be_a(Hash)
      expect(registrations.keys).to include(:prism)
    end
  end
end
