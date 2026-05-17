# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Ast::Merge::Git do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  it "conforms to the git merge3 contract fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-950-git-merge3-contract", "git-merge3-contract.json"))
    expect(fixture.dig(:contract, :package)).to eq("ast-merge-git")
    expect(fixture.dig(:contract, :operation)).to eq("merge3")

    fixture.fetch(:cases).each do |test_case|
      result = described_class.merge3(test_case.fetch(:request))
      expected = test_case.fetch(:expected)

      expect(result.fetch(:ok)).to eq(expected.fetch(:ok)), test_case.fetch(:case_id)
      expect(result.fetch(:conflicts).length).to eq(expected.fetch(:conflict_count)), test_case.fetch(:case_id)
      expect(result.fetch(:reparse_after_render)).to eq(expected.fetch(:reparse_after_render))
      if result.fetch(:ok)
        expect(JSON.parse(result.fetch(:merged_source))).to eq(JSON.parse(JSON.generate(expected.fetch(:merged_json))))
      else
        expect(result.fetch(:conflicts).map { |conflict| conflict.fetch(:category) }).to eq(expected.fetch(:conflict_categories))
        expect(result.fetch(:conflicts).map { |conflict| conflict.fetch(:path) }).to eq(expected.fetch(:conflict_paths))
        expected.fetch(:conflicted_source_contains, []).each do |needle|
          expect(result.fetch(:conflicted_source)).to include(needle), test_case.fetch(:case_id)
        end
      end
    end
  end
end
