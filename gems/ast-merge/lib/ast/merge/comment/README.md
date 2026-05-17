# Ast::Merge::Comment

`Ast::Merge::Comment` provides a generic comment model that merge implementations can reuse across languages.

## Comment styles

Built-in styles are registered in `Ast::Merge::Comment::Style`:

- `:hash_comment`
- `:html_comment`
- `:c_style_line`
- `:c_style_block`
- `:semicolon_comment`
- `:double_dash_comment`

Lookup uses `Style.for`:

```ruby
style = Ast::Merge::Comment::Style.for(:hash_comment)
style.line_start # => "#"
```

You can inspect available styles with `Style.available_styles` and register custom ones with `Style.register(...)`.

## Core node types

### `Line`

`Ast::Merge::Comment::Line` represents a single comment line.

```ruby
line = Ast::Merge::Comment::Line.new(
  text: "# frozen_string_literal: true",
  line_number: 1,
  style: :hash_comment,
)

line.content
line.signature
line.freeze_action("ast-merge")
```

### `Block`

`Ast::Merge::Comment::Block` groups contiguous comment content.
It can be built either from child line nodes or from raw block-comment text.

```ruby
block = Ast::Merge::Comment::Block.new(
  children: [
    Ast::Merge::Comment::Line.new(text: "# one", line_number: 1),
    Ast::Merge::Comment::Line.new(text: "# two", line_number: 2),
  ],
)
```

### `Empty`

`Ast::Merge::Comment::Empty` represents a blank line that should be preserved as part of comment structure.

```ruby
empty = Ast::Merge::Comment::Empty.new(line_number: 3, text: "")
```

## Parsing comment content

`Ast::Merge::Comment::Parser` turns an array of lines into comment nodes.

```ruby
nodes = Ast::Merge::Comment::Parser.parse(
  ["# heading", "", "# details"],
  style: :hash_comment,
)
```

Use `style: :auto` to detect the style from the first non-empty line.

## Merge-facing helpers in this namespace

The namespace also contains reusable helpers for comment-aware mergers:

- `Attachment`
- `Augmenter`
- `Capability`
- `Region`
- `RegionMergePolicy`
- `TrackedHashAdapter`

These support comment attachment and region-aware merge behavior in format-specific gems.

## Freeze markers

Comment nodes expose helpers for freeze-marker detection:

- `freeze_action(token)`
- `freeze_marker?(token)`
- `freeze?(token)`
- `unfreeze?(token)`

That keeps freeze detection consistent across comment syntaxes.

## When to use this namespace

Use `Ast::Merge::Comment` when a merge implementation needs:

- normalized comment nodes with signatures
- shared handling for line comments, block comments, and blank lines
- comment-aware freeze markers or attachment logic

Format-specific comment semantics still belong in the corresponding `*-merge` gem.
