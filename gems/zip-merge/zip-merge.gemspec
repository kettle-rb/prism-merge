# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "zip-merge"
  spec.version = "0.0.0"
  spec.summary = "ZIP merge planning and rendering helpers for Structured Merge"
  spec.authors = ["Structured Merge"]
  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "tree_haver", ">= 0"
end
