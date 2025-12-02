#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test to verify PrismMerge loads and works

require "prism/merge"

puts "=== Testing PrismMerge ==="
puts

# Test 1: Module loads
puts "✓ Prism::Merge module loaded"

# Test 2: Simple merge
template = <<~RUBY
  # frozen_string_literal: true

  def hello
    puts "world"
  end
RUBY

destination = <<~RUBY
  # frozen_string_literal: true

  def hello
    puts "world"
  end
RUBY

begin
  merger = Prism::Merge::SmartMerger.new(template, destination)
  puts "✓ SmartMerger instantiated"

  result = merger.merge
  puts "✓ Merge completed"

  puts
  puts "=== Result ==="
  puts result
  puts

  stats = merger.result.statistics
  puts "=== Statistics ==="
  stats.each do |decision, count|
    puts "  #{decision}: #{count}"
  end

  puts
  puts "✓ All tests passed!"
rescue StandardError => e
  puts "✗ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit(1)
end
