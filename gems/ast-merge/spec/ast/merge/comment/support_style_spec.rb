# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::SupportStyle do
  describe "legacy constructor aliases" do
    it "normalizes source-augmented synthetic to the portable-write style" do
      support_style = described_class.source_augmented_synthetic(
        source: :fixture_source,
        capability: :full,
        style: :hash_comment,
      )

      expect(support_style.style).to eq(:source_augmented_portable_write)
      expect(support_style).to be_source_augmented_portable_write
      expect(support_style).to be_source_augmented_synthetic
      expect(support_style).to be_portable_write
      expect(support_style).to be_synthetic_write
    end

    it "normalizes native-read synthetic-write to the portable-write style" do
      support_style = described_class.native_read_synthetic_write(
        source: :fixture_native,
        capability: :full,
        style: :hash_comment,
      )

      expect(support_style.style).to eq(:native_read_portable_write)
      expect(support_style).to be_native_read_portable_write
      expect(support_style).to be_native_read_synthetic_write
      expect(support_style).to be_portable_write
      expect(support_style).to be_synthetic_write
    end
  end

  describe "#initialize" do
    it "accepts legacy style names and normalizes them" do
      support_style = described_class.new(
        style: :source_augmented_synthetic,
        details: {source: :fixture_source, capability: :full, style: :hash_comment},
      )

      expect(support_style.style).to eq(:source_augmented_portable_write)
      expect(support_style).to be_source_augmented_synthetic
    end
  end
end
