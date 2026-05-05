# frozen_string_literal: true

require_relative "lib/kettle/jem/version"

Gem::Specification.new do |spec|
  spec.name = "kettle-jem"
  spec.version = Kettle::Jem::VERSION
  spec.authors = ["Structured Merge Contributors"]
  spec.email = ["opensource@structuredmerge.dev"]

  spec.summary = "RubyGems package templating wrapper for Structured Merge"
  spec.description = "RubyGems-focused recipe-pack wrapper that shapes package facts into ast-merge transport."
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

  spec.add_dependency "ast-merge", "= #{Kettle::Jem::VERSION}"
  spec.add_dependency "token-resolver", "~> 1.0", ">= 1.0.2"
end
