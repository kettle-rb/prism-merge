# StructuredMerge Ruby

StructuredMerge Ruby provides Ruby gems for building merge-aware tools that need
portable structured-merge contracts, fixture-backed behavior, and Ruby-native
integration points.

The monorepo includes the core AST/review contracts, parser substrate support,
format-specific merge gems, binary/ZIP planning helpers, provider adapters, and
a Ruby packaging recipe gem.

Project links:

- Website: <https://structuredmerge.org>
- Implementations: <https://structuredmerge.org/implementations.html>
- Specification: <https://github.com/structuredmerge/structuredmerge-spec>
- Shared fixtures: <https://github.com/structuredmerge/structuredmerge-fixtures>

## Install

Install the gems your tool needs:

```sh
bundle add ast-merge json-merge
```

## Command

The Ruby implementation ships the implementation-specific `smorg-rb` command.
Use that name in git configuration unless a package manager or local install has
provided a `smorg` symlink.

```sh
git config merge.smorg-rb.driver 'smorg-rb merge-driver %O %A %B %P'
git config diff.smorg-rb.command 'smorg-rb diff-driver'
smorg-rb conflicts diff path/to/file-with-conflicts.go
smorg-rb languages --gitattributes
```

`merge-driver` updates Git's `%A` file by default, or writes to `--output` when
used outside git. `diff-driver` accepts both the two-argument local form and the
seven- or nine-argument forms Git passes to external diff commands.
`conflicts diff` reports conflict-marker regions in a file that already contains
Git conflict markers.

## Gems

Core:

- [`tree_haver`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver) - parser substrate, byte ranges, backend adapters, and binary tree contracts.
- [`ast-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge) - AST merge contracts, diagnostics, planning, review, replay, and nested-merge vocabulary.
- [`ast-template`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template) - template/session transport contracts.

Format libraries:

- [`plain-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge)
- [`json-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge)
- [`yaml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/yaml-merge)
- [`toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/toml-merge)
- [`markdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge)
- [`ruby-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ruby-merge)
- [`go-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/go-merge)
- [`rust-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rust-merge)
- [`typescript-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/typescript-merge)
- [`binary-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/binary-merge)
- [`zip-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/zip-merge)

Provider and recipe gems:

- [`psych-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge)
- [`citrus-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge)
- [`parslet-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge)
- [`commonmarker-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge)
- [`kramdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge)
- [`markly-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge)
- [`prism-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge)
- [`kettle-jem`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem)

## Portability

The Ruby gems are developed against the shared StructuredMerge fixtures. Those
fixtures define the cross-language behavior expected from the Go, TypeScript,
Rust, and Ruby implementations. Conformance checks live in gem specs and in the
shared spec/fixture tooling rather than in a static launch-status document.

## Development

Common checks:

- `mise run check`
- `bundle exec rake`
- package-specific `bundle exec rspec` commands

Bundler path gems are the default isolation mechanism inside this monorepo. When
this repository needs to consume sibling workspace projects outside the monorepo
itself, prefer `nomono`-driven Bundler wiring rather than manual Ruby load-path
changes.
