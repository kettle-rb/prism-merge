# frozen_string_literal: true

require "json"
require "pathname"
require "version_gem/rspec"
require "rspec/stubbed_env"
require_relative "../../../spec/bootstrap/tree_haver_backends"
require_relative "../../../spec/bootstrap/merge_gems"

require "ast/merge"
require "ast/merge/rspec/dependency_tags_config"
require "ast/merge/rspec/shared_examples"
require "markdown-merge"
require "toml-merge"
require "ruby-merge"

require_relative "support/testable_node"
require_relative "support/fictive_language_harness"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include RSpec::StubbedEnv::StubHelpers
  config.include RSpec::StubbedEnv::HideHelpers

  config.before do
    allow(described_class).to receive(:sleep) if described_class&.respond_to?(:sleep)
  end

  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
