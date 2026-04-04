#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Frozen dest node leading comment deduplication
#
# Demonstrates that when a template-only node and a frozen destination node
# share the same leading comment block, the merged output contains that block
# exactly once.
#
# Scenario:
#   - Template has `kettle-dev` (template-only) with "# NOTE: ..." as leading comment
#   - Dest has `bundler-audit` frozen (kettle-jem:freeze) which also has
#     "# NOTE: ..." as a Prism-native leading comment
#   - Expected: NOTE block appears exactly once in merged output

WORKSPACE_ROOT = File.expand_path("../..", __dir__)
ENV["KETTLE_RB_DEV"] = WORKSPACE_ROOT unless ENV.key?("KETTLE_RB_DEV")

require "bundler/inline"

gemfile do
  source "https://gem.coop"
  require File.expand_path("nomono/lib/nomono/bundler", WORKSPACE_ROOT)

  eval_nomono_gems(
    gems: %w[ast-merge tree_haver prism-merge],
    prefix: "KETTLE_RB",
    path_env: "KETTLE_RB_DEV",
    vendored_gems_env: "VENDORED_GEMS",
    vendor_gem_dir_env: "VENDOR_GEM_DIR",
    debug_env: "KETTLE_DEV_DEBUG"
  )
end

require "prism/merge"

template = <<~RUBY
  # frozen_string_literal: true
  Gem::Specification.new do |spec|
    spec.executables = ["foo"]
    spec.add_dependency("version_gem", "~> 1.1")
    # NOTE: It is preferable.
    #       More text.
    # Dev, Test
    spec.add_development_dependency("kettle-dev", "~> 2.0")
    # Security
    spec.add_development_dependency("bundler-audit", "~> 0.9.3")
  end
RUBY

dest = <<~RUBY
  # frozen_string_literal: true
  Gem::Specification.new do |spec|
    spec.executables = ["foo"]
    # kettle-jem:freeze
    # Runtime deps note.
    # kettle-jem:unfreeze
    # NOTE: It is preferable.
    #       More text.
    # Security
    spec.add_development_dependency("bundler-audit", "~> 0.9.3")
  end
RUBY

merger = Prism::Merge::SmartMerger.new(
  template, dest,
  preference: :template,
  add_template_only_nodes: true,
  freeze_token: "kettle-jem",
)
result = merger.merge

puts result

note_count = result.scan("NOTE: It is preferable").length
status = note_count == 1 ? "PASS" : "FAIL"
puts "--- NOTE count: #{note_count} (expected 1) [#{status}]"
