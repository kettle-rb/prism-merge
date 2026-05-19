# frozen_string_literal: true

require "tree_haver"

registry = TreeHaver::BackendRegistry

{
  commonmarker_backend: {
    backend_name: :commonmarker,
    require_path: "commonmarker/merge",
  },
  markly_backend: {
    backend_name: :markly,
    require_path: "markly/merge",
  },
  kramdown_backend: {
    backend_name: :kramdown,
    require_path: "kramdown/merge",
  },
  prism_backend: {
    backend_name: :prism,
    require_path: "prism/merge",
  },
  psych_backend: {
    backend_name: :psych,
    require_path: "psych/merge",
  },
  citrus_backend: {
    backend_name: :citrus,
    require_path: "citrus/toml/merge",
  },
  parslet_backend: {
    backend_name: :parslet,
    require_path: "parslet/toml/merge",
  },
}.each do |tag_name, metadata|
  registry.register_tag(tag_name, category: :backend, **metadata) do
    !registry.fetch(metadata.fetch(:backend_name).to_s).nil?
  end
end

registry.register_tag(:rbs_gem, category: :gem, backend_name: :rbs_gem, require_path: "rbs/merge") do
  defined?(::RBS)
end

require "tree_haver/rspec/dependency_tags"
