# frozen_string_literal: true

require "json"
require "pathname"
require "version_gem/rspec"
require "ast/merge/rspec/setup"
require "ast/merge"
require "tree_haver"
require "dotenv/merge"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
