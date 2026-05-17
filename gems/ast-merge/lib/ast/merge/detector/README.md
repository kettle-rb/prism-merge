# Ast::Merge::Detector

`Ast::Merge::Detector` contains raw-text region detectors and the mixin used to fold those regions into a merge workflow.

## Region model

`Ast::Merge::Detector::Region` is the value object returned by detectors.
It carries:

- `type`
- `content`
- `start_line`
- `end_line`
- `delimiters`
- `metadata`

Helpful methods include:

- `line_range`
- `line_count`
- `full_text`
- `contains_line?`
- `overlaps?`

## Building a detector

Subclass `Ast::Merge::Detector::Base` and implement:

- `region_type`
- `detect_all(source)`

Use `build_region(...)` to construct `Region` instances.

```ruby
class MermaidDetector < Ast::Merge::Detector::Base
  def region_type
    :mermaid_code_block
  end

  def detect_all(source)
    []
  end
end
```

## Built-in detectors

### `FencedCodeBlock`

Detects Markdown fenced code blocks for a specific language.

```ruby
ruby_blocks = Ast::Merge::Detector::FencedCodeBlock.ruby
json_blocks = Ast::Merge::Detector::FencedCodeBlock.json
regions = ruby_blocks.detect_all(markdown_source)
```

The class also includes convenience constructors such as:

- `.ruby`
- `.json`
- `.yaml`
- `.toml`
- `.mermaid`
- `.javascript`
- `.typescript`
- `.python`
- `.bash`

### `YamlFrontmatter`

Detects YAML frontmatter at the start of a document.

```ruby
regions = Ast::Merge::Detector::YamlFrontmatter.new.detect_all(document)
```

### `TomlFrontmatter`

Detects TOML frontmatter at the start of a document.

```ruby
regions = Ast::Merge::Detector::TomlFrontmatter.new.detect_all(document)
```

## Region-aware merging with `Mergeable`

`Ast::Merge::Detector::Mergeable` is mixed into `SmartMergerBase`.
It lets a merger:

1. extract configured regions from template and destination text
2. replace those regions with placeholders during the parent merge
3. merge region content with specialized mergers
4. substitute merged regions back into the final output

Typical configuration:

```ruby
merger = SomeMerger.new(
  template,
  destination,
  regions: [
    {
      detector: Ast::Merge::Detector::YamlFrontmatter.new,
      merger_class: Psych::Merge::SmartMerger,
      merger_options: {preference: :destination},
    },
    {
      detector: Ast::Merge::Detector::FencedCodeBlock.ruby,
      merger_class: Prism::Merge::SmartMerger,
    },
  ],
)
```

Nested region configs are supported through the `:regions` key on each region config.

## When to use detectors

Use detector-based regions when structure is easiest to identify from source text:

- fenced code blocks inside Markdown
- frontmatter blocks
- other delimited text regions

When a format already exposes the region naturally in its parsed AST, the format-specific merger can work directly with that AST instead of raw-text detection.
