#!/usr/bin/env ruby
# frozen_string_literal: true

require "markdown/merge"

template = <<~MARKDOWN
  # Template Project

  ## Synopsis

  Template synopsis.

  ## Basic Usage

  Template usage.

  ## Support

  File issues with a small reproduction.
MARKDOWN

destination = <<~MARKDOWN
  # Destination Project

  ## Synopsis

  Destination-owned synopsis with project-specific details.

  ## Basic Usage

  Destination-owned usage example.
MARKDOWN

result = Markdown::Merge.merge_markdown(template, destination, "markdown")
abort result.fetch(:diagnostics).inspect unless result.fetch(:ok)

puts result.fetch(:output)
