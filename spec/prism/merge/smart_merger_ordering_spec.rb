# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "ordering of destination-only content" do
    it "preserves destination-only lines that come before template content" do
      template = <<~RUBY
        # frozen_string_literal: true

        class A
        end
      RUBY

      dest = <<~RUBY
        # frozen_string_literal: true

        # dest-only header
        EXTRA = :value

        class A
        end
      RUBY

      result = described_class.new(template, dest, preference: :template).merge

      # dest-only content should be present
      expect(result).to include("dest-only header")
      expect(result).to include("EXTRA = :value")
      expect(result).to include("class A")
    end

    it "preserves destination-only lines that come after template content" do
      template = <<~RUBY
        # frozen_string_literal: true

        class A
        end
      RUBY

      dest = <<~RUBY
        # frozen_string_literal: true

        class A
        end

        # dest-only footer
        FOOTER = true
      RUBY

      result = described_class.new(template, dest, preference: :template).merge
      expect(result).to include("FOOTER = true")
      expect(result).to include("dest-only footer")
    end
  end
end
