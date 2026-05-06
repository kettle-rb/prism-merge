# frozen_string_literal: true

require_relative "lib/zip/merge/version"

Gem::Specification.new do |spec|
  spec.name = "zip-merge"
  spec.version = Zip::Merge::VERSION
  spec.authors = ["Structured Merge Contributors"]
  spec.email = ["info@structuredmerge.org"]
  spec.summary = "Structured Merge ZIP merge planning and rendering helpers for Ruby"
  spec.description = "Portable ZIP inventory, planning, nested dispatch, and raw-preservation rendering helpers for Structured Merge."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.add_dependency "tree_haver", "= #{Zip::Merge::VERSION}"
end
