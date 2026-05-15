# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Ast::Crispr do
  it "conforms to the ast-crispr package boundary fixture" do
    fixture_path = Pathname(__dir__).join(
      "..",
      "..",
      "..",
      "..",
      "fixtures",
      "diagnostics",
      "slice-916-ast-crispr-package-boundary",
      "ast-crispr-package-boundary.json"
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    expect(described_class.boundary_report).to eq(fixture.fetch(:boundary))
    expect(described_class.ast_merge_contract_anchor).to eq("Ast::Merge.structured_edit")
  end
end
