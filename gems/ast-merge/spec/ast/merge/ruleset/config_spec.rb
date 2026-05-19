# frozen_string_literal: true

RSpec.describe Ast::Merge::Ruleset::Config do
  let(:valid_ruleset) do
    <<~RULESET
      # comment

      format toml
      owners line_bound_statements
      match signature
      read native_read_portable_write
      attach normalize_tracked_layout_merge
      comment_style hash_comment
      render toml_pairs_and_tables
      capability inline_comments true
      capability quoted_hash_inline_literals false
      logical_owner link_definition preserve_if_referenced
      repair comment_ownership_overlap warn
      surface fenced_code_block language_tag
      delegate fenced_code_block by_language
    RULESET
  end

  describe ".parse" do
    it "parses a valid compact ruleset" do
      ruleset = described_class.parse(valid_ruleset)

      expect(ruleset.to_h).to include(
        format: :toml,
        owners: :line_bound_statements,
        match: :signature,
        read: :native_read_portable_write,
        attach: :normalize_tracked_layout_merge,
        comment_style: :hash_comment,
        render: :toml_pairs_and_tables,
      )
      expect(ruleset.capabilities).to eq(
        inline_comments: true,
        quoted_hash_inline_literals: false,
      )
      expect(ruleset.logical_owners).to eq(
        link_definition: :preserve_if_referenced,
      )
      expect(ruleset.repair_policies.map(&:to_h)).to eq(
        [{kind: :comment_ownership_overlap, handling: :warn, metadata: {}}],
      )
      expect(ruleset.surfaces.map(&:to_h)).to eq(
        [{name: :fenced_code_block, selector: :language_tag, metadata: {}}],
      )
      expect(ruleset.delegation_policies.map(&:to_h)).to eq(
        [{surface_name: :fenced_code_block, strategy: :by_language, metadata: {}}],
      )
    end

    it "tracks parsed directives with line numbers" do
      ruleset = described_class.parse(valid_ruleset)

      expect(ruleset.directives.first).to include(name: :format, line_number: 3)
      expect(ruleset.directives.last).to include(name: :delegate)
    end

    it "rejects missing required directives" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      }.to raise_error(ArgumentError, /missing required directives: match/)
    end

    it "rejects unknown directives" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
          frobnicate yes
        RULESET
      }.to raise_error(ArgumentError, /Unknown directive frobnicate/)
    end

    it "rejects duplicate required directives" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          format yaml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      }.to raise_error(ArgumentError, /Duplicate directive format/)
    end

    it "rejects unknown read strategies" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read mystery_strategy
          attach normalize_tracked_layout_merge
        RULESET
      }.to raise_error(ArgumentError, /Unknown read strategy/)
    end

    it "rejects unknown attachment strategies" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach mystery_strategy
        RULESET
      }.to raise_error(ArgumentError, /Unknown attach strategy/)
    end

    it "rejects unknown owner selectors" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners mystery_owner
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      }.to raise_error(ArgumentError, /Unknown owner selector/)
    end

    it "rejects unknown match keys" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match mystery_match
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      }.to raise_error(ArgumentError, /Unknown match key/)
    end

    it "rejects invalid token content" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
          render bad#token
        RULESET
      }.to raise_error(ArgumentError, /Invalid token/)
    end

    it "rejects duplicate capability names" do
      expect {
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
          capability inline_comments true
          capability inline_comments false
        RULESET
      }.to raise_error(ArgumentError, /Duplicate capability inline_comments/)
    end

    it "rejects duplicate logical owner names" do
      expect {
        described_class.parse(<<~RULESET)
          format markdown
          owners link_definitions
          match normalized_reference
          read source_augmented_portable_write
          attach tracker_layout_merge
          logical_owner link_definition preserve_if_referenced
          logical_owner link_definition preserve_always
        RULESET
      }.to raise_error(ArgumentError, /Duplicate logical_owner link_definition/)
    end
  end

  describe ".load" do
    let(:fixture_path) { File.expand_path("../../../fixtures/rulesets/basic_toml.ruleset", __dir__) }

    it "loads and parses a ruleset file" do
      ruleset = described_class.load(fixture_path)

      expect(ruleset.path).to eq(fixture_path)
      expect(ruleset.format).to eq(:toml)
      expect(ruleset.read).to eq(:native_read_portable_write)
    end
  end

  describe "#support_style" do
    it "bridges parsed read strategy to a support style value object" do
      ruleset = described_class.parse(valid_ruleset)
      support_style = ruleset.support_style(source: :toml_native, capability: :full)

      expect(support_style.native_read_portable_write?).to be(true)
      expect(support_style.details[:source]).to eq(:toml_native)
      expect(support_style.details[:style]).to eq(:hash_comment)
    end

  end

  describe "#feature_profile" do
    it "carries repair policies, surfaces, and delegation policies into the shared profile" do
      ruleset = described_class.parse(valid_ruleset)
      profile = ruleset.feature_profile

      expect(profile.repair_policies.map(&:to_h)).to eq(
        [{kind: :comment_ownership_overlap, handling: :warn, metadata: {}}],
      )
      expect(profile.surfaces.map(&:to_h)).to eq(
        [{name: :fenced_code_block, selector: :language_tag, metadata: {}}],
      )
      expect(profile.delegation_policies.map(&:to_h)).to eq(
        [{surface_name: :fenced_code_block, strategy: :by_language, metadata: {}}],
      )
    end
  end
end
