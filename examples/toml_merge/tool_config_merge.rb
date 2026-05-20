#!/usr/bin/env ruby
# frozen_string_literal: true

require "toml/merge"

template = <<~TOML
  [tool.structuredmerge]
  enabled = true
  strategy = "semantic"

  [tool.structuredmerge.backends]
  json = "tree-sitter"
  markdown = "tree-sitter"
TOML

destination = <<~TOML
  [tool.structuredmerge]
  strategy = "destination-policy"

  [tool.local]
  cache = true
TOML

result = Toml::Merge.merge_toml(template, destination, "toml")
abort result.fetch(:diagnostics).inspect unless result.fetch(:ok)

puts result.fetch(:output)

