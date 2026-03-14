# frozen_string_literal: true

RSpec.describe Prism::Merge::BeginNodeStructure do
  def parse_first_statement(source)
    Prism.parse(source).value.statements.body.first
  end

  describe "#boundary_lines" do
    it "returns begin/rescue/else/ensure/end boundaries for a BeginNode" do
      source = <<~RUBY
        begin
          work
        rescue StandardError => e
          recover(e)
        else
          success_state = :after_success
        ensure
          cleanup
        end
      RUBY

      structure = described_class.new(parse_first_statement(source))

      expect(structure.boundary_lines).to eq([1, 3, 5, 7, 9])
    end
  end

  describe "#clause_regions" do
    it "computes clause regions for rescue, else, and ensure" do
      source = <<~RUBY
        begin
          work
        rescue StandardError => e
          recover(e)
        else
          success_state = :after_success
        ensure
          cleanup
        end
      RUBY

      structure = described_class.new(parse_first_statement(source))

      expect(structure.clause_regions).to eq([
        {type: [:rescue_clause, [:standard_error], 0], start_line: 3, end_line: 4},
        {type: :else_clause, start_line: 5, end_line: 6},
        {type: :ensure_clause, start_line: 7, end_line: 8},
      ])
    end
  end

  describe "#clause_nodes_by_type" do
    it "indexes clauses by type and rescue occurrence" do
      source = <<~RUBY
        begin
          work
        rescue StandardError => e
          recover(e)
        rescue StandardError => e
          retry_state = :retry_recover
        ensure
          cleanup
        end
      RUBY

      structure = described_class.new(parse_first_statement(source))
      clause_nodes = structure.clause_nodes_by_type

      expect(clause_nodes.keys).to eq([
        [:rescue_clause, [:standard_error], 0],
        [:rescue_clause, [:standard_error], 1],
        :ensure_clause,
      ])
      expect(clause_nodes[:ensure_clause]).to be_a(Prism::EnsureNode)
    end
  end

  describe "#line_map_for" do
    it "maps matching clause start lines between BeginNodes" do
      template = <<~RUBY
        begin
          work

        rescue StandardError => e
          recover(e)
        ensure
          cleanup
        end
      RUBY

      dest = <<~RUBY
        begin
          work
        rescue StandardError => e
          recover(e)
        ensure
          cleanup
        end
      RUBY

      template_structure = described_class.new(parse_first_statement(template))
      dest_structure = described_class.new(parse_first_statement(dest))

      expect(template_structure.line_map_for(dest_structure)).to eq({4 => 3, 6 => 5})
    end
  end

  describe "#has_clause_or_body?" do
    it "returns true for clause-only BeginNode wrappers" do
      source = <<~RUBY
        begin
        rescue StandardError => e
          recover(e)
        end
      RUBY

      structure = described_class.new(parse_first_statement(source))

      expect(structure.has_clause_or_body?).to be true
      expect(structure.clause_start_line).to eq(2)
    end
  end
end
