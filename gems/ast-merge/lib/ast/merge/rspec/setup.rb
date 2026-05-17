# frozen_string_literal: true

# Ast::Merge RSpec Setup (Registry Only)
#
# This file loads ONLY the registry and helper classes without configuring RSpec.
# It's used in the ast-merge test suite to allow registering known gems before
# SimpleCov loads the library code.
#
# DO NOT load this in merge gem test suites - they should use require "ast/merge/rspec"
# which includes the full RSpec configuration.
#
# @example Loading in ast-merge's spec_helper.rb (BEFORE requiring ast-merge)
#   require "ast/merge/rspec/setup"
#
#   # Now you can register known gems:
#   Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(:markly_merge, :prism_merge)
#
# @example For merge gem test suites (normal pattern)
#   # Don't use this file! Use the full loader instead:
#   require "ast/merge/rspec"  # Loads setup + RSpec configuration

# Load only the registry - no RSpec configuration
require_relative "merge_gem_registry"
require_relative "dependency_tags_helpers"
