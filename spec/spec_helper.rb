# frozen_string_literal: true

# External RSpec & related config
require "kettle/test/rspec"

# Internal ENV config
require_relative "config/debug"

# Config for development dependencies of this library
# i.e., not configured by this library
#
# Simplecov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for older rubies won't have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# this library
require "prism/merge"

RSpec.configure do |config|
  # Auto-skip examples that require Bundler >= 2.7 (which implies Ruby >= 3.2)
  config.before(:each, :bundler_27_only) do
    # Skip on Ruby < 3.2 using rspec-pending_for's version matcher
    skip_for(reason: "Requires Bundler >= 2.7 which is unavailable on Ruby < 3.2", versions: %w[2.3 2.4 2.5 2.6 2.7 3.0 3.1])
  end

  config.before do
    # Speed up polling loops
    allow(described_class).to receive(:sleep) unless described_class.nil?
  end
end
