# frozen_string_literal: true

# Test method calls with various argument patterns
configure do |config|
  config.setting = "template value"
end

setup(name: "app", version: "1.0")

process_data("input.txt", mode: :read)

run_task("build", ["--verbose", "--optimize"])
