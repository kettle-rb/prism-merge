#!/usr/bin/env ruby
# frozen_string_literal: true

require "json/merge"
require "markdown/merge"
require "ruby/merge"
require "toml/merge"
require "yaml/merge"

profiles = {
  json: Json::Merge.json_feature_profile,
  markdown: Markdown::Merge.markdown_backend_feature_profile,
  ruby: Ruby::Merge.ruby_backend_feature_profile,
  toml: Toml::Merge.toml_backend_feature_profile,
  yaml: Yaml::Merge.yaml_backend_feature_profile
}

profiles.each do |family, profile|
  puts "\n== #{family} =="
  profile.each do |key, value|
    puts "#{key}: #{value.inspect}"
  end
end

