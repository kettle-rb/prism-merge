#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "json/merge"

template = JSON.pretty_generate(
  {
    "name" => "template-package",
    "version" => "2.0.0",
    "private" => true,
    "scripts" => {
      "test" => "bundle exec rake",
      "lint" => "bundle exec rubocop"
    },
    "structuredMerge" => {
      "families" => ["json", "markdown", "ruby"]
    }
  }
)

destination = JSON.pretty_generate(
  {
    "name" => "customer-package",
    "version" => "1.4.3",
    "scripts" => {
      "test" => "bundle exec rspec",
      "release" => "bundle exec rake release"
    }
  }
)

result = Json::Merge.merge_json(template, destination, "json")
abort result.fetch(:diagnostics).inspect unless result.fetch(:ok)

puts result.fetch(:output)
