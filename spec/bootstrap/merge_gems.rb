# frozen_string_literal: true

require "ast/merge/rspec/setup"

registry = Ast::Merge::RSpec::MergeGemRegistry

{
  markly_merge: {
    require_path: "markly/merge",
    merger_class: "Markly::Merge::SmartMerger",
    test_source: "# Test\n\nParagraph",
    category: :markdown,
  },
  commonmarker_merge: {
    require_path: "commonmarker/merge",
    merger_class: "Commonmarker::Merge::SmartMerger",
    test_source: "# Test\n\nParagraph",
    category: :markdown,
  },
  markdown_merge: {
    require_path: "markdown/merge",
    merger_class: "Markdown::Merge::SmartMerger",
    test_source: "# Test\n\nParagraph",
    category: :markdown,
    skip_instantiation: true,
  },
  prism_merge: {
    require_path: "prism/merge",
    merger_class: "Prism::Merge::SmartMerger",
    test_source: "def foo; end",
    category: :code,
  },
  bash_merge: {
    require_path: "bash/merge",
    merger_class: "Bash::Merge::SmartMerger",
    test_source: "#!/bin/bash\necho hello",
    category: :code,
  },
  rbs_merge: {
    require_path: "rbs/merge",
    merger_class: "Rbs::Merge::SmartMerger",
    test_source: "class Foo\nend",
    category: :code,
  },
  json_merge: {
    require_path: "json/merge",
    merger_class: "Json::Merge::SmartMerger",
    test_source: '{"key": "value"}',
    category: :data,
  },
  toml_merge: {
    require_path: "toml/merge",
    merger_class: "Toml::Merge::SmartMerger",
    test_source: "[section]\nkey = \"value\"",
    category: :config,
  },
  psych_merge: {
    require_path: "psych/merge",
    merger_class: "Psych::Merge::SmartMerger",
    test_source: "key: value",
    category: :config,
  },
  dotenv_merge: {
    require_path: "dotenv/merge",
    merger_class: "Dotenv::Merge::SmartMerger",
    test_source: "KEY=value",
    category: :config,
  },
}.each do |tag_name, metadata|
  registry.register_known_gem(tag_name, **metadata)
end

registry.register_known_gems(*registry.known_gems.keys)
