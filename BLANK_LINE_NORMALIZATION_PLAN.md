# Blank Line Normalization Plan for `prism-merge`

_Date: 2026-03-19_

## Role in the family refactor

`prism-merge` is the native Ruby reference adopter for the shared blank-line normalization effort.

It already contains meaningful gap-preservation logic and should be one of the first repos migrated onto the new shared `ast-merge` layout model.

## Current evidence files

Primary implementation files:

- `lib/prism/merge/smart_merger.rb`
- `lib/prism/merge/node_emission_support.rb`
- `lib/prism/merge/file_analysis.rb`
- `lib/prism/merge/merge_result.rb`

Relevant specs:

- `spec/prism/merge/smart_merger_spec.rb`
- `spec/prism/merge/merge_result_spec.rb`
- `spec/prism/merge/removal_mode_compliance_spec.rb`
- `spec/prism/merge/comment_only_file_merger_spec.rb`
- `spec/integration/magic_comment_handling_spec.rb`

## Current pressure points

`prism-merge` already handles blank lines in several Ruby-specific contexts:

- destination prefix lines and header gaps
- blank lines between top-level blocks
- blank lines between leading comments and code
- separator blank lines around preserved promoted comments in removal mode
- comment-only file behavior

This makes it the best real-world proving ground for the shared `ast-merge` layout model.

## Migration targets

### 1. Replace bespoke top-level gap emission with shared layout semantics

Move behavior currently centered in `node_emission_support` onto shared `ast-merge` gap objects and emit helpers where possible.

### 2. Preserve Ruby-specific semantics while sharing generic gap handling

Ruby-specific handling must remain explicit for:

- shebang lines
- magic comments
- header-only treatment
- freeze-marker interactions

Those semantics stay in `prism-merge`; only generic blank-line behavior should migrate.

### 3. Use shared policies for exact vs normalized spacing

`prism-merge` should explicitly choose shared policies for:

- exact preserved destination gaps
- exact preserved template gaps when template wins
- normalized separator blank lines in removal-mode promotion paths where that is the intended contract

## Workstreams

### Workstream A: map current bespoke behavior

Inventory current gap rules in:

- destination-only emission
- matched-node emission
- removed-node comment promotion
- comment-only file merge flow

### Workstream B: adopt shared layout objects

- consume `Ast::Merge::Layout::*` once available
- minimize direct line-number gap reconstruction in repo-local code

### Workstream C: strengthen regression coverage

Add or align focused coverage for:

- blank lines at file start before code
- blank lines between top-level Ruby blocks
- blank lines between leading comments and nodes
- stable separator blank lines after comment promotion
- idempotence across repeated merges

## Exit criteria

- repo-local blank-line heuristics are reduced in favor of shared `ast-merge` layout helpers
- Ruby-specific semantics remain correct
- focused and integration specs continue to validate exact gap preservation where intended
- `prism-merge` serves as the strongest reference implementation for the family
