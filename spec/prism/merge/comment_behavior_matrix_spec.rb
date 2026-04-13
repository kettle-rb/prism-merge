# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe "prism comment behavior matrix" do
  include_examples "Ast::Merge::CommentBehaviorMatrix" do
    let(:comment_matrix_analysis_class) { Prism::Merge::FileAnalysis }
    let(:comment_matrix_merger_class) { Prism::Merge::SmartMerger }
    let(:comment_matrix_source_builder) { ->(*lines) { "#{lines.join("\n")}\n" } }
    let(:comment_matrix_comment_line_builder) { ->(text, indent: "") { "#{indent}# #{text}" } }
    let(:comment_matrix_capabilities) do
      {
        preamble_floating_split: "native Prism leading-comment attachment keeps the first detached line-1 block with the first owner",
      }
    end
    let(:comment_matrix_owner_value_reader) { ->(owner) { owner.value.unescaped } }
    let(:comment_matrix_expected_literal_hash_value) { "literal # hash" }
    let(:comment_matrix_line_builder) do
      lambda do |name, value, inline: nil|
        line = "#{name} = #{value}"
        inline ? "#{line} # #{inline}" : line
      end
    end
  end
end
