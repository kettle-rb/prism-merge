# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  it_behaves_like "Ast::Merge::RemovalModeCompliance" do
    let(:merger_class) { described_class }

    let(:removal_mode_leading_comments_case) do
      {
        template: <<~RUBY,
          KEEP = true
        RUBY
        destination: <<~RUBY,
          # docs for old setting
          OLD = true
          KEEP = true
        RUBY
        expected: <<~RUBY,
          # docs for old setting
          KEEP = true
        RUBY
        options: {preference: :template},
      }
    end

    let(:removal_mode_inline_comments_case) do
      {
        template: <<~RUBY,
          KEEP = true
        RUBY
        destination: <<~RUBY,
          OLD = true # keep inline
          KEEP = true
        RUBY
        expected: <<~RUBY,
          # keep inline
          KEEP = true
        RUBY
        options: {preference: :template},
      }
    end

    let(:removal_mode_separator_blank_line_case) do
      {
        template: <<~RUBY,
          KEEP = true
        RUBY
        destination: <<~RUBY,
          # docs for old setting
          OLD = true # keep inline

          # trailing note

          KEEP = true
        RUBY
        expected: <<~RUBY,
          # docs for old setting
          # keep inline

          # trailing note

          KEEP = true
        RUBY
        options: {preference: :template},
      }
    end

    let(:removal_mode_recursive_case) do
      {
        template: <<~RUBY,
          class Example
            def shared
              :template
            end
          end
        RUBY
        destination: <<~RUBY,
          class Example
            # helper docs
            def helper
              :dest_only
            end

            def shared
              :destination
            end
          end
        RUBY
        expected: <<~RUBY,
          class Example
            # helper docs

            def shared
              :template
            end
          end
        RUBY
        options: {preference: :template},
      }
    end
  end
end
