# frozen_string_literal: true

RSpec.describe Prism::Merge::NodeBodyLayout do
  def build_merger(source)
    Prism::Merge::SmartMerger.new(source, source)
  end

  def first_node(merger)
    merger.template_analysis.statements.first
  end

  describe "wrapper/body boundaries" do
    it "extracts opening-line block body content without folding it into the header" do
      source = <<~RUBY
        task do |task_name| shared_call; custom_call
          later_call
        end
      RUBY

      merger = build_merger(source)
      layout = described_class.new(node: first_node(merger), analysis: merger.template_analysis, merger: merger)

      expect(layout.opening_line_text).to eq("task do |task_name| ")
      expect(layout.body_text).to eq(<<~RUBY)
        shared_call; custom_call
          later_call
      RUBY
      expect(layout.closing_line_text).to eq("end")
    end

    it "maps extracted body lines back to their original wrapper source lines" do
      source = <<~RUBY
        class Config
          def updated
            :template
          end

          def custom
            :destination
          end
        end
      RUBY

      merger = build_merger(source)
      layout = described_class.new(node: first_node(merger), analysis: merger.template_analysis, merger: merger)

      expect((1..7).map { |line| layout.source_line_for_body_line(line) }).to eq([2, 3, 4, 5, 6, 7, 8])
    end
  end
end
