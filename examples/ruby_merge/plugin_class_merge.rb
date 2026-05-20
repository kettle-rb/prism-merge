#!/usr/bin/env ruby
# frozen_string_literal: true

require "ruby/merge"

template = <<~RUBY
  require "json"

  class Plugin
    def call(payload)
      JSON.generate(payload)
    end

    def metadata
      { source: "template" }
    end
  end
RUBY

destination = <<~RUBY
  class Plugin
    def call(payload)
      payload.fetch(:custom)
    end
  end
RUBY

result = Ruby::Merge.merge_ruby(
  template,
  destination,
  "ruby",
  merge_template_requires: true
)
abort result.fetch(:diagnostics).inspect unless result.fetch(:ok)

puts result.fetch(:output)

