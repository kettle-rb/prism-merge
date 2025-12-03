# frozen_string_literal: true

# Destination has same calls but different block content
configure do |config|
  config.setting = "destination value"
  config.extra = "custom"
end

setup(name: "app", version: "1.0")

process_data("input.txt", mode: :read)

run_task("build", ["--verbose", "--optimize"])

# Destination-only call
cleanup("temp")
