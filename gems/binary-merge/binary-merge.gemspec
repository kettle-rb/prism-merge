# frozen_string_literal: true

require_relative "lib/binary/merge/version"

Gem::Specification.new do |spec|
  spec.name = "binary-merge"
  spec.version = Binary::Merge::VERSION
  spec.authors = ["Structured Merge Contributors"]
  spec.email = ["opensource@structuredmerge.dev"]

  spec.summary = "Structured Merge binary merge contracts for Ruby"
  spec.description = "Portable binary preservation planning and diagnostics for Structured Merge."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  root = __dir__
  spec.files = Dir.chdir(root) do
    Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |path| File.directory?(path) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "tree_haver", "= #{Binary::Merge::VERSION}"
end
