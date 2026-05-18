# frozen_string_literal: true

require "json"
require "pathname"
require "version_gem/rspec"
require "ast/merge/rspec/setup"
require "ast/merge"
require "tree_haver"
require "rbs/merge"

%w[mri ffi rust java rbs].each do |legacy_backend_id|
  next if TreeHaver::BackendRegistry.fetch(legacy_backend_id)

  TreeHaver::BackendRegistry.register(
    TreeHaver::BackendReference.new(id: legacy_backend_id, family: "tree-sitter")
  )
end

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |path| require path }

def register_rbs_merge_backend!
  Rbs::Merge::BACKEND_REGISTRY.registered = false
  Rbs::Merge.register_backend!
end

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.before(:each, :rbs_parser) do
    skip "RBS parser runtime is not available" unless defined?(::RBS::Parser)
  end

  config.before(:each, :mri_backend) do
    skip "TreeHaver MRI backend is not available" unless TreeHaver.const_defined?(:Backends) &&
      TreeHaver::Backends.const_defined?(:MRI) &&
      TreeHaver::Backends::MRI.available?
  end

  config.before(:each, :ffi_backend) do
    skip "TreeHaver FFI backend is not available" unless TreeHaver.const_defined?(:Backends) &&
      TreeHaver::Backends.const_defined?(:FFI) &&
      TreeHaver::Backends::FFI.available?
  end

  config.before(:each, :rust_backend) do
    skip "TreeHaver Rust backend is not available" unless TreeHaver.const_defined?(:Backends) &&
      TreeHaver::Backends.const_defined?(:Rust) &&
      TreeHaver::Backends::Rust.available?
  end

  config.before(:each, :java_backend) do
    skip "TreeHaver Java backend is not available" unless TreeHaver.const_defined?(:Backends) &&
      TreeHaver::Backends.const_defined?(:Java) &&
      TreeHaver::Backends::Java.available?
  end

  config.before do
    TreeHaver::LanguageRegistry.clear_cache!
    register_rbs_merge_backend!
  end

  config.after do
    TreeHaver::LanguageRegistry.clear_cache!
    TreeHaver.reset_backend!(to: :auto) if TreeHaver.respond_to?(:reset_backend!)
  end

  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
