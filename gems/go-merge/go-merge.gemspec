# frozen_string_literal: true

require_relative "lib/go/merge/version"

Gem::Specification.new do |spec|
  spec.name = "go-merge"
  spec.version = Go::Merge::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["info@structuredmerge.org"]
  spec.summary = "Structured Merge Go module analysis and merge for Ruby"
  spec.description = "Portable Go module owner analysis and merge behavior for Structured Merge."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["homepage_uri"] = "https://structuredmerge.org"
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  root = __dir__
  spec.files = Dir.chdir(root) { Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |path| File.directory?(path) } }
  spec.require_paths = ["lib"]
  spec.add_dependency "ast-merge", "= #{Go::Merge::VERSION}"
  spec.add_dependency "tree_haver", "= #{Go::Merge::VERSION}"
end
