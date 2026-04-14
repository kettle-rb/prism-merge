# frozen_string_literal: true

require "spec_helper"

RSpec.describe "nocov ownership when the close marker trails a statement" do
  let(:source) do
    <<~RUBY
      begin
        require_relative "fence/kramdown_gfm_document"
      # :nocov:
      rescue LoadError => error
        if error.message.include?("kramdown")
          warn("missing kramdown")
        else
          raise error
        end
      end
      # :nocov:

      module Yard
      end
    RUBY
  end

  it "raises instead of silently merging a syntactically misaligned nocov pair" do
    expect do
      Prism::Merge::SmartMerger.new(
        source,
        source,
        preference: :template,
        add_template_only_nodes: true,
        dest_path: "lib/yard/fence.rb",
      ).merge
    end.to raise_error(Prism::Merge::TemplateParseError, /same syntactic level/)
  end
end
