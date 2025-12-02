# frozen_string_literal: true

# Template with conditional
if ENV["DEBUG"]
  puts "Debug mode enabled"
end

def process_data(data)
  data.map(&:upcase)
end
