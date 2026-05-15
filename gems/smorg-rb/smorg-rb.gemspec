# frozen_string_literal: true

require_relative "lib/smorg/rb/version"

Gem::Specification.new do |spec|
  spec.name = "smorg-rb"
  spec.version = Smorg::RB::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["info@structuredmerge.org"]
  spec.summary = "Implementation-specific StructuredMerge command for Ruby"
  spec.description = "Git-compatible StructuredMerge command surface for the Ruby implementation."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.files = Dir["lib/**/*.rb"] + Dir["exe/*"]
  spec.bindir = "exe"
  spec.executables = ["smorg-rb"]
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = "https://structuredmerge.org"
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "ast-merge", "= #{Smorg::RB::VERSION}"
  spec.add_dependency "go-merge", "= #{Smorg::RB::VERSION}"
  spec.add_dependency "json-merge", "= #{Smorg::RB::VERSION}"
  spec.add_dependency "plain-merge", "= #{Smorg::RB::VERSION}"
end
