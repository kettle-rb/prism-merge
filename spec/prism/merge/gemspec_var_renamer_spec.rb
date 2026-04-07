# frozen_string_literal: true

RSpec.describe Prism::Merge::GemspecVarRenamer do
  describe ".rename" do
    it "renames simple assignment receivers" do
      source = <<~RUBY
        gem.name = "mylib"
        gem.version = "1.0"
        gem.authors = ["Alice"]
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to include("spec.name")
      expect(result).to include("spec.version")
      expect(result).to include("spec.authors")
      expect(result).not_to include("gem.")
    end

    it "renames chained receiver calls (metadata[])" do
      source = <<~RUBY
        gem.metadata["homepage_uri"] = "https://example.com"
        gem.metadata["source_code_uri"] = "https://github.com/example"
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to include('spec.metadata["homepage_uri"]')
      expect(result).to include('spec.metadata["source_code_uri"]')
      expect(result).not_to include("gem.")
    end

    it "renames method call receivers (add_dependency)" do
      source = <<~RUBY
        gem.add_dependency("foo", "~> 1.0")
        gem.add_development_dependency("bar", "~> 2.0")
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to include('spec.add_dependency("foo"')
      expect(result).to include('spec.add_development_dependency("bar"')
      expect(result).not_to include("gem.")
    end

    it "handles mixed receiver types in one source" do
      source = <<~RUBY
        gem.name = "mylib"
        gem.metadata["key"] = "value"
        gem.add_dependency("foo", "~> 1.0")
        gem.files = Dir["lib/**/*.rb"]
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      lines = result.lines
      expect(lines[0]).to start_with("spec.name")
      expect(lines[1]).to start_with('spec.metadata["key"]')
      expect(lines[2]).to start_with("spec.add_dependency")
      expect(lines[3]).to start_with("spec.files")
      expect(result).not_to include("gem.")
    end

    it "does not rename unrelated variables" do
      source = <<~RUBY
        gem.name = "mylib"
        config.value = 42
        other.something = true
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to include("spec.name")
      expect(result).to include("config.value")
      expect(result).to include("other.something")
    end

    it "returns source unchanged when old_var == new_var" do
      source = "spec.name = \"mylib\"\n"
      result = described_class.rename(source, old_var: "spec", new_var: "spec")

      expect(result).to eq(source)
    end

    it "returns source unchanged when empty" do
      result = described_class.rename("", old_var: "gem", new_var: "spec")

      expect(result).to eq("")
    end

    it "returns source unchanged when no matching receivers exist" do
      source = <<~RUBY
        config.name = "mylib"
        puts "hello"
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to eq(source)
    end

    it "handles string interpolation containing the variable" do
      source = <<~RUBY
        gem.metadata["homepage_uri"] = "https://\#{gem.name}.example.com/"
        gem.description = "A \#{gem.name} library"
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to include("spec.metadata")
      expect(result).to include("spec.description")
      # Interpolated references should also be renamed
      expect(result).to include('#{spec.name}')
      expect(result).not_to include("gem.")
    end

    it "handles single-character variable names" do
      source = <<~RUBY
        s.name = "mylib"
        s.version = "1.0"
      RUBY

      result = described_class.rename(source, old_var: "s", new_var: "spec")

      expect(result).to include("spec.name")
      expect(result).to include("spec.version")
      expect(result).not_to match(/\bs\./)
    end

    it "handles longer-to-shorter variable rename" do
      source = <<~RUBY
        spec.name = "mylib"
        spec.metadata["key"] = "value"
      RUBY

      result = described_class.rename(source, old_var: "spec", new_var: "s")

      expect(result).to include("s.name")
      expect(result).to include('s.metadata["key"]')
    end

    it "preserves indentation and whitespace" do
      source = "  gem.name    = \"mylib\"\n  gem.version = \"1.0\"\n"

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result.lines[0]).to eq("  spec.name    = \"mylib\"\n")
      expect(result.lines[1]).to eq("  spec.version = \"1.0\"\n")
    end

    it "handles rdoc_options and array-style assignments" do
      source = <<~RUBY
        gem.rdoc_options += [
          "--title",
          "\#{gem.name} - \#{gem.summary}",
          "--main",
          "README.md",
        ]
      RUBY

      result = described_class.rename(source, old_var: "gem", new_var: "spec")

      expect(result).to include("spec.rdoc_options")
      expect(result).to include('#{spec.name}')
      expect(result).to include('#{spec.summary}')
      expect(result).not_to include("gem.")
    end
  end
end
