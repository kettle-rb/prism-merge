# frozen_string_literal: true

RSpec.describe "Gemspec variable renaming integration" do
  describe "dest-only attributes with different block variable" do
    it "renames dest-only node receivers to match template variable" do
      template = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name    = "mylib"
          spec.version = "1.0"
          spec.authors = ["Alice"]
        end
      RUBY

      dest = <<~RUBY
        Gem::Specification.new do |gem|
          gem.name    = "mylib"
          gem.version = "0.9"
          gem.authors = ["Alice"]
          gem.summary = "A great library"
          gem.homepage = "https://example.com"
          gem.metadata["funding_uri"] = "https://fund.me"
          gem.add_dependency("foo", "~> 1.0")
          gem.add_development_dependency("bar", "~> 2.0")
        end
      RUBY

      result = Prism::Merge::SmartMerger.new(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
      ).merge
      output = result.to_s

      # Matched nodes use template values
      expect(output).to include("spec.name")
      expect(output).to include("spec.version")
      expect(output).to include("spec.authors")

      # Dest-only nodes must use the template's variable name (spec, not gem)
      expect(output).to include("spec.summary")
      expect(output).to include("spec.homepage")
      expect(output).to include('spec.metadata["funding_uri"]')
      expect(output).to include("spec.add_dependency")
      expect(output).to include("spec.add_development_dependency")

      # No leftover gem. references anywhere
      expect(output).not_to include("gem.")
    end

    it "renames dest-only nodes when dest uses 's' and template uses 'spec'" do
      template = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "mylib"
        end
      RUBY

      dest = <<~RUBY
        Gem::Specification.new do |s|
          s.name = "mylib"
          s.required_ruby_version = ">= 2.7"
          s.metadata["rubygems_mfa_required"] = "true"
        end
      RUBY

      result = Prism::Merge::SmartMerger.new(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
      ).merge
      output = result.to_s

      expect(output).to include("spec.required_ruby_version")
      expect(output).to include('spec.metadata["rubygems_mfa_required"]')
      expect(output).not_to match(/\bs\./)
    end

    it "always uses template variable name regardless of preference" do
      template = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "mylib"
          spec.required_ruby_version = ">= 3.0"
          spec.add_development_dependency("rake", "~> 13.0")
        end
      RUBY

      dest = <<~RUBY
        Gem::Specification.new do |gem|
          gem.name = "mylib"
        end
      RUBY

      result = Prism::Merge::SmartMerger.new(
        template,
        dest,
        preference: :destination,
        add_template_only_nodes: true,
      ).merge
      output = result.to_s

      # Template variable name always wins (pipeline assumes canonical var)
      expect(output).to include("spec.required_ruby_version")
      expect(output).to include("spec.add_development_dependency")
      expect(output).to include("spec.name")
      expect(output).not_to include("gem.")
    end

    it "handles rdoc_options with += and string interpolation" do
      template = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "mylib"
        end
      RUBY

      dest = <<~RUBY
        Gem::Specification.new do |gem|
          gem.name = "mylib"
          gem.rdoc_options += [
            "--title",
            "\#{gem.name} - docs",
          ]
        end
      RUBY

      result = Prism::Merge::SmartMerger.new(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
      ).merge
      output = result.to_s

      expect(output).to include("spec.rdoc_options")
      expect(output).to include('#{spec.name}')
      expect(output).not_to include("gem.")
    end

    it "does not alter output when both sides use the same variable" do
      template = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "mylib"
          spec.version = "1.0"
        end
      RUBY

      dest = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "mylib"
          spec.summary = "Great lib"
        end
      RUBY

      result = Prism::Merge::SmartMerger.new(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
      ).merge
      output = result.to_s

      expect(output).to include("spec.name")
      expect(output).to include("spec.version")
      expect(output).to include("spec.summary")
    end
  end
end
