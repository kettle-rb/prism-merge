# frozen_string_literal: true

# Standard configuration
CONFIG = {
  name: "template",
}

# kettle-dev:freeze
CUSTOM_CONFIG = {
  secret: "should be preserved",
}
# kettle-dev:unfreeze

def standard_method
  puts "template version"
end
