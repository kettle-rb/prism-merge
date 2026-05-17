# Ast::Merge::Layout

`Ast::Merge::Layout` contains the shared blank-line ownership model used by `ast-merge` and the sibling `*-merge` gems.

The namespace answers a merge-specific question: when a run of blank lines sits between two structural owners, how can both owners be aware of the same layout while only one side controls output?

## Core types

### `Gap`

`Ast::Merge::Layout::Gap` is the passive value object for a contiguous blank-line run.

A gap records:

- `kind` (`:preamble`, `:interstitial`, or `:postlude`)
- `start_line`
- `end_line`
- `lines`
- `before_owner`
- `after_owner`
- `controller_side`
- `metadata`

Helpful methods include:

- `preamble?`
- `interstitial?`
- `postlude?`
- `line_count`
- `blank_line_count`
- `controller`
- `fallback_controller`
- `leading_for?(owner)`
- `trailing_for?(owner)`
- `controls_output_for?(owner, ...)`

Controller defaults follow the tested ownership rules:

- preamble gaps are controlled by the following owner
- postlude gaps are controlled by the preceding owner
- interstitial gaps default to the following owner and can fall back to the preceding owner if needed

### `Attachment`

`Ast::Merge::Layout::Attachment` is the per-owner view of adjacent gaps.

An attachment can expose:

- `leading_gap`
- `trailing_gap`
- `gaps`
- `empty?`
- `leading_controls_output?(...)`
- `trailing_controls_output?(...)`

This lets adjacent owners reference the same shared gap object without duplicating output responsibility.

### `Augmenter`

`Ast::Merge::Layout::Augmenter` infers shared layout state from source lines plus owner ranges.

It builds:

- `preamble_gap`
- `interstitial_gaps`
- `postlude_gap`
- `attachments_by_owner`
- `attachment_for(owner)`
- `gaps`

A minimal example:

```ruby
require "ast/merge"

Owner = Struct.new(:start_line, :end_line, :label, keyword_init: true)

first = Owner.new(start_line: 2, end_line: 2, label: :first)
second = Owner.new(start_line: 4, end_line: 4, label: :second)

augmenter = Ast::Merge::Layout::Augmenter.new(
  lines: ["", "alpha", "", "beta", ""],
  owners: [first, second],
)

first_attachment = augmenter.attachment_for(first)
second_attachment = augmenter.attachment_for(second)
shared_gap = augmenter.interstitial_gaps.first

augmenter.preamble_gap.kind              # => :preamble
shared_gap.kind                          # => :interstitial
augmenter.postlude_gap.kind              # => :postlude
first_attachment.trailing_gap.equal?(shared_gap)  # => true
second_attachment.leading_gap.equal?(shared_gap)  # => true
second_attachment.leading_controls_output?        # => true
```

If owners do not expose `#start_line` and `#end_line` directly, you can supply extractors with `start_line_for:` and `end_line_for:`.

## Using Layout through `FileAnalyzable`

`Ast::Merge::FileAnalyzable` exposes the Layout namespace through two merge-facing hooks:

- `layout_attachment_for(owner, **options)`
- `layout_augmenter(owners: nil, **options)`

That gives a format-specific `FileAnalysis` class a shared API for blank-line ownership.

```ruby
analysis = SomeMerge::FileAnalysis.new(source)
owners = analysis.statements

augmenter = analysis.layout_augmenter(owners: owners)
attachment = analysis.layout_attachment_for(owners.first)
```

The default implementation infers directly adjacent blank-line runs from `lines` and the owners' line ranges. A format-specific analysis can override these hooks if it needs a stronger or more specialized ownership model.

## Ownership model in practice

The key idea is shared awareness without duplicate emission:

- both adjacent owners may reference the same interstitial gap
- only one owner controls that gap's output at a time
- if the primary controlling owner is removed, control can fall back to the surviving adjacent owner

This makes exact blank-line preservation and removal-mode behavior predictable across different merge implementations.

## When to use this namespace

Use `Ast::Merge::Layout` when a merger needs:

- exact tracking of blank-line runs around structural owners
- a reusable ownership model for preamble, interstitial, and postlude gaps
- per-owner attachment objects that can participate in merge decisions
- a shared contract that works across parser-backed and synthetic analyses

Format-specific parsing logic still belongs in the corresponding `FileAnalysis` implementation; `Ast::Merge::Layout` is the shared abstraction that sits on top of those owner ranges.
