# frozen_string_literal: true

# Destination with same conditional but different body
if ENV["DEBUG"]
  puts "Debug mode"
  puts "Verbose logging enabled"
end

def process_data(data)
  data.map(&:upcase)
end
