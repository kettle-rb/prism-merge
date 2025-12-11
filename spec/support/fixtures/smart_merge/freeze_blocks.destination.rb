# frozen_string_literal: true

# Standard configuration
CONFIG = {
  name: "destination",
}

# kettle-dev:freeze
# Destination has freeze marker - this node should be preserved
CUSTOM_CONFIG = {
  secret: "destination secret",
  api_key: "abc123",
}

def standard_method
  puts "destination version"
end

def custom_method
  puts "destination only"
end
