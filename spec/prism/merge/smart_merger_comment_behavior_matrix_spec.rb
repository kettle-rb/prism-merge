# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Prism::Merge::SmartMerger do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like "Ast::Merge::CommentBehaviorMatrix" do
    line_based_comment_matrix_adapter(
      analysis_class: Prism::Merge::FileAnalysis,
      merger_class: described_class,
      comment_line_builder: ->(text, indent: "") { "#{indent}# #{text}" },
      structural_owners_reader: ->(analysis) { analysis.statements },
      owner_value_reader: ->(owner) { owner.value.unescaped },
      line_builder: lambda do |name, value, inline: nil|
        line = "#{name} = #{value}"
        inline ? "#{line} # #{inline}" : line
      end,
      capabilities: {},
      expected_literal_hash_value: "literal # hash",
    )
  end

  describe "duplicate template-owned preamble prefix handling" do
    let(:template) do
      <<~RUBY
        # Shared header

        alpha = 1
      RUBY
    end

    let(:destination) do
      <<~RUBY
        # Shared header
        # Shared header
        # Destination header
        alpha = 9
      RUBY
    end

    it "heals suspected duplicate-prefix corruption by default" do
      merged = described_class.new(template, destination, add_template_only_nodes: true).merge

      expect(merged).to eq(<<~RUBY)
        # Destination header
        alpha = 9
      RUBY
    end

    it "can skip healing to expose the raw duplicated behavior" do
      merged = described_class.new(
        template,
        destination,
        add_template_only_nodes: true,
        corruption_handling: :skip,
      ).merge

      expect(merged).to eq(destination)
    end

    it "can warn instead of healing" do
      expect do
        described_class.new(
          template,
          destination,
          add_template_only_nodes: true,
          corruption_handling: :warn,
        ).merge
      end.to output(/Suspected corruption \(duplicate_template_leading_prefix\)/).to_stderr
    end

    it "can raise instead of healing" do
      expect do
        described_class.new(
          template,
          destination,
          add_template_only_nodes: true,
          corruption_handling: :error,
        ).merge
      end.to raise_error(
        Prism::Merge::CorruptionDetectedError,
        /duplicate_template_leading_prefix/,
      )
    end
  end
end
