# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "with freeze blocks" do
    let(:signature_generator) do
      lambda do |node|
        case node
        when Prism::CallNode
          case node.name
          when :source
            [:source]
          when :gem
            [:gem, node.arguments.arguments.first.content]
          else
            [node.name]
          end
        else
          [node.class]
        end
      end
    end

    it "adds template-only nodes even when freeze blocks are present" do
      src_content = <<~RUBY
        source "https://example.com"
        gem "foo"
      RUBY

      dest_content = <<~RUBY
        source "https://rubygems.org"
        # kettle-dev:freeze
        gem "bar", "~> 1.0"
        # kettle-dev:unfreeze
      RUBY

      merger = described_class.new(
        src_content,
        dest_content,
        signature_match_preference: :template,
        add_template_only_nodes: true,
        signature_generator: signature_generator,
      )
      result = merger.merge
      puts result

      expected_output = <<~RUBY
        source "https://example.com"
        gem "foo"
        # kettle-dev:freeze
        gem "bar", "~> 1.0"
        # kettle-dev:unfreeze
      RUBY

      # Normalize whitespace and newlines for comparison
      normalized_result = result.gsub(/\s+/, " ").strip
      expected_output.gsub(/\s+/, " ").strip

      expect(normalized_result).to include('gem "foo"')
    end
  end
end
