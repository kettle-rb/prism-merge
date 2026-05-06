# StructuredMerge Ruby

Ruby implementation of the StructuredMerge contract.

This repository is one of four peer launch implementations: [Go](https://github.com/structuredmerge/structuredmerge-go), [TypeScript](https://github.com/structuredmerge/structuredmerge-typescript), [Rust](https://github.com/structuredmerge/structuredmerge-rust), and [Ruby](https://github.com/structuredmerge/structuredmerge-ruby). The language repos are not separate products. They consume the same public spec and shared fixture corpus so tools can choose the runtime surface that fits their environment.

Project links:

- Website: <https://structuredmerge.org>
- Implementations overview: <https://structuredmerge.org/implementations.html>
- Conformance model: <https://structuredmerge.org/conformance.html>
- Specification: <https://github.com/structuredmerge/structuredmerge-spec>
- Shared fixtures: <https://github.com/structuredmerge/structuredmerge-fixtures>

## Workspace

This is a Ruby monorepo for StructuredMerge packages.

Package directories:

- [`ast-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge)
- [`ast-template`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template)
- [`binary-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/binary-merge)
- [`citrus-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge)
- [`commonmarker-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge)
- [`go-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/go-merge)
- [`json-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge)
- [`kettle-jem`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem)
- [`kramdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge)
- [`markdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge)
- [`markly-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge)
- [`parslet-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge)
- [`prism-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge)
- [`psych-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge)
- [`ruby-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ruby-merge)
- [`rust-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rust-merge)
- [`plain-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge)
- [`toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/toml-merge)
- [`tree_haver`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver)
- [`typescript-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/typescript-merge)
- [`yaml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/yaml-merge)
- [`zip-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/zip-merge)

## Conformance

Integration tests should consume the shared fixture corpus from the sibling `../structuredmerge-fixtures` checkout. A ruleset, fixture, diagnostic shape, or review outcome should mean the same thing whether exercised through Go, TypeScript, Rust, or Ruby.

Use the spec repository's conformance matrix for the current launch-readiness snapshot:

- <https://github.com/structuredmerge/structuredmerge-spec/blob/main/conformance-matrix.md>
- <https://github.com/structuredmerge/structuredmerge-spec/blob/main/IMPLEMENTATION_STATUS.md>

## Development

Standard repo tasks are exposed through `mise` and native Ruby tooling.

Common checks:

- `mise run check`
- `bundle exec rake` or package-specific tests

Bundler path gems are the default isolation mechanism inside this monorepo. When this repository needs to consume sibling workspace projects outside the monorepo itself, prefer `nomono`-driven Bundler wiring rather than manual Ruby load-path changes.

## Status

Early implementation work. Public compatibility claims should be tied to shared fixtures and documented conformance status rather than runtime-specific assumptions.
