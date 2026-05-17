# Ast::Merge::Text

`Ast::Merge::Text` is the concrete, line-oriented merger that ships with `ast-merge`.
It serves two purposes:

- a working reference implementation for new `*-merge` gems
- a lightweight merger for plain-text content

## Core types

### `LineNode`

Top-level statements are `LineNode` instances. A line node carries its source line number, raw content, normalized content, and child `WordNode` instances.

### `WordNode`

`WordNode` is the leaf node used by the text AST. It gives the text implementation nested structure without requiring a format-specific parser.

### `FileAnalysis`

`Ast::Merge::Text::FileAnalysis` includes `Ast::Merge::FileAnalyzable` and turns source text into mergeable statements.

It also detects freeze blocks using the `text-merge` token by default.

```ruby
analysis = Ast::Merge::Text::FileAnalysis.new("one\ntwo\n")
analysis.statements
analysis.valid?
```

## Merge flow

### `SmartMerger`

`Ast::Merge::Text::SmartMerger` subclasses `SmartMergerBase` and delegates the batch merge to `Text::ConflictResolver`.

Important return values:

- `merge` returns the merged text as a `String`
- `merge_result` returns the `Ast::Merge::Text::MergeResult` object

```ruby
template = "alpha\nbeta\ngamma\n"
destination = "alpha\ncustom\nbeta\n"

merger = Ast::Merge::Text::SmartMerger.new(
  template,
  destination,
  preference: :destination,
  add_template_only_nodes: true,
)

merged_text = merger.merge
result = merger.merge_result
```

### `ConflictResolver`

`Ast::Merge::Text::ConflictResolver` uses batch resolution with destination-order preservation:

- matching lines are resolved by preference
- destination-only lines are preserved
- template-only lines are appended when `add_template_only_nodes: true`
- destination freeze blocks are always preserved

### `MergeResult`

`Ast::Merge::Text::MergeResult` extends `MergeResultBase` with line-oriented helpers:

- `add_line`
- `add_lines`
- `record_decision`

## Freeze blocks

The text merger recognizes hash-comment freeze markers:

```text
# text-merge:freeze keep this block
custom content
# text-merge:unfreeze
```

You can supply a different token through `freeze_token:`.

## Section splitting

The text namespace also includes utilities for splitting text into named sections.

### `Section`

`Ast::Merge::Text::Section` is a small value object with:

- `name`
- `header`
- `body`
- `start_line`
- `end_line`
- `metadata`

### `SectionSplitter`

`Ast::Merge::Text::SectionSplitter` is an abstract base for section-based text merging.

### `LineSectionSplitter`

`Ast::Merge::Text::LineSectionSplitter` is the concrete splitter included in this gem.
It splits text using a line regex and capture group.

```ruby
splitter = Ast::Merge::Text::LineSectionSplitter.new(
  pattern: /^##\s+(.+)$/,
)

sections = splitter.split(markdown_text)
merged = splitter.merge(template_text, destination_text, add_template_only: true)
```

## When to reach for this namespace

Use `Ast::Merge::Text` when you want:

- a small end-to-end example of an `ast-merge` implementation
- a merger for line-oriented formats
- section splitting driven by regular expressions rather than a full parser

For structured formats such as Ruby, YAML, JSON, or Markdown, the format-specific `*-merge` gem remains the better fit.
