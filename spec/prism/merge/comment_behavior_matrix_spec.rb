# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe "prism comment behavior matrix" do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  include_examples "Ast::Merge::CommentBehaviorMatrix" do
    line_based_comment_matrix_adapter(
      analysis_class: Prism::Merge::FileAnalysis,
      merger_class: Prism::Merge::SmartMerger,
      comment_line_builder: ->(text, indent: "") { "#{indent}# #{text}" },
      structural_owners_reader: ->(analysis) { analysis.statements },
      owner_value_reader: ->(owner) { owner.value.unescaped },
      line_builder: lambda do |name, value, inline: nil|
        line = "#{name} = #{value}"
        inline ? "#{line} # #{inline}" : line
      end,
      capabilities: {
        preamble_floating_split: "native Prism leading-comment attachment keeps the first detached line-1 block with the first owner",
      },
      expected_literal_hash_value: "literal # hash",
    )
  end
end
