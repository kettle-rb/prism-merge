# frozen_string_literal: true

require_relative "lib/ast/crispr/version"

Gem::Specification.new do |spec|
  spec.name = "ast-crispr"
  spec.version = Ast::Crispr::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["info@structuredmerge.org"]

  spec.summary = "Structured edit tooling over Structured Merge AST contracts"
  spec.description = "A thin structural edit tool layer over ast-merge structured-edit contracts."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.files = Dir["lib/**/*.rb"]
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

  spec.add_dependency "ast-merge", "= #{Ast::Crispr::VERSION}"
  spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.9"
end
