# frozen_string_literal: true

# Standard configuration
CONFIG = {
  name: "template",
}

# Template version of CUSTOM_CONFIG (no freeze marker)
CUSTOM_CONFIG = {
  secret: "should be preserved",
}

def standard_method
  puts "template version"
end
