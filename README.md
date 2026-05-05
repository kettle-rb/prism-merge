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

Initial packages:

- `tree-haver`
- `ast-merge`
- `text-merge`
- `json-merge`
- `toml-merge`
- `yaml-merge`
- source-family packages for TypeScript, Rust, Go, and Ruby cases

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
