# frozen_string_literal: true

RSpec.describe Prism::Merge::SmartMerger do
  describe "freeze marker as leading comment" do
    # In the simplified model, a freeze marker is a leading comment on a node.
    # The node that has `# kettle-dev:freeze` in its leading_comments is "frozen"
    # and will always prefer the destination version during merge.
    #
    # No closing marker is needed - the node's boundary IS the freeze boundary.

    context "when dest node has freeze marker in leading comment" do
      it "preserves dest version of frozen node even when template differs" do
        template = <<~RUBY
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "example"
          end
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          gem_version = "2.0.0-custom"

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = gem_version
            spec.authors = ["Custom Author"]
          end
        RUBY

        merger = described_class.new(
          template,
          dest,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        # The frozen gem_version should be preserved from dest
        expect(result).to include('gem_version = "2.0.0-custom"')
        expect(result).not_to include('gem_version = "1.0.0"')

        # The freeze marker comment should appear exactly once
        freeze_count = result.scan("kettle-dev:freeze").length
        expect(freeze_count).to eq(1), <<~MSG
          Expected 1 freeze marker but got #{freeze_count}.
          The freeze marker is a leading comment on gem_version assignment.

          Result:
          #{result}
        MSG
      end

      it "does not duplicate frozen nodes" do
        template = <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          # Custom comment block
          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "example"
          end
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          # Custom comment block
          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = gem_version
          end
        RUBY

        merger = described_class.new(
          template,
          dest,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        # Should have exactly 1 freeze marker (not duplicated)
        freeze_count = result.scan("kettle-dev:freeze").length
        expect(freeze_count).to eq(1), <<~MSG
          Expected 1 freeze marker but got #{freeze_count}.
          When template and dest have the same frozen node, it should appear once.

          Result:
          #{result}
        MSG

        # gem_version should appear exactly once
        gem_version_count = result.scan("gem_version = ").length
        expect(gem_version_count).to eq(1), <<~MSG
          Expected gem_version assignment to appear once but got #{gem_version_count}.

          Result:
          #{result}
        MSG
      end
    end

    context "when dest has dest-only frozen content" do
      it "preserves dest-only nodes with freeze markers" do
        template = <<~RUBY
          # frozen_string_literal: true

          def foo; end
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          def foo; end

          # kettle-dev:freeze
          # This custom method should be preserved
          def custom_method
            :preserved
          end
        RUBY

        merger = described_class.new(
          template,
          dest,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        expect(result).to include("# kettle-dev:freeze")
        expect(result).to include("def custom_method")
        expect(result).to include(":preserved")

        # Should have exactly 1 freeze marker
        freeze_count = result.scan("kettle-dev:freeze").length
        expect(freeze_count).to eq(1)
      end
    end

    context "regression: gemspec-like content" do
      it "handles gemspec with frozen gem_version" do
        template = <<~RUBY
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
          end
        RUBY

        dest = <<~RUBY
          # frozen_string_literal: true

          # kettle-dev:freeze
          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
            spec.authors = ["Author"]
          end
        RUBY

        merger = described_class.new(
          template,
          dest,
          freeze_token: "kettle-dev",
        )
        result = merger.merge

        # Count freeze markers - should have exactly 1
        freeze_count = result.scan("kettle-dev:freeze").length

        expect(freeze_count).to eq(1), <<~MSG
          Expected 1 freeze marker but got #{freeze_count}.

          Result:
          #{result}
        MSG

        # The frozen gem_version from dest should be used
        expect(result).to include("# kettle-dev:freeze")
        expect(result).to include('gem_version = "1.0.0"')
      end
    end
  end
end
