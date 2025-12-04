# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- Recursive merge support for class and module bodies - nested structures are now merged intelligently
- Conditional signature matching for `if`/`unless` blocks based on condition expression
- Freeze block validation for partial/incomplete nodes and freeze blocks inside non-class/module contexts
- Freeze blocks now match by position/order when both files have multiple freeze blocks
- `add_template_only_nodes` option now properly respected in recursive merges and boundary processing
- `DebugLogger`, controlled by `ENV["PRISM_MERGE_DEBUG"]` set to true or false
- more specs

### Changed

- Migrated to Prism v1.6.0 native comment attachment (removed custom comment association logic)
- Simplified FileAnalysis implementation using Prism's built-in features
- Improved node lookup to handle anchors with leading comments (e.g., magic comments)

### Fixed

- Template-only nodes are now correctly excluded in all contexts when `add_template_only_nodes: false`
- Freeze blocks inside methods now properly raise InvalidStructureError (only class/module-level freeze blocks allowed)
- Freeze block matching now works correctly with multiple consecutive freeze blocks (matches by index/order)
- Duplicate freeze blocks from template no longer appear when destination has matching freeze blocks
- Magic comments at file top no longer prevent node lookup in recursive merges

### Security

## [1.0.3] - 2025-12-03

- TAG: [v1.0.3][1.0.3t]
- COVERAGE: 95.48% -- 613/642 lines in 7 files
- BRANCH COVERAGE: 81.39% -- 188/231 branches in 7 files
- 100.00% documented

### Added

- Improved synopsis documentation

### Fixed

- More fixes to Ruby compatibility documentation (down to Ruby 2.7)

## [1.0.2] - 2025-12-03

- TAG: [v1.0.2][1.0.2t]
- COVERAGE: 95.48% -- 613/642 lines in 7 files
- BRANCH COVERAGE: 81.39% -- 188/231 branches in 7 files
- 100.00% documented

### Added

- specs covering existing support for end-of-line comments

### Fixed

- Ruby compatibility documentation

## [1.0.1] - 2025-12-03

- TAG: [v1.0.1][1.0.1t]
- COVERAGE: 95.48% -- 613/642 lines in 7 files
- BRANCH COVERAGE: 81.39% -- 188/231 branches in 7 files
- 100.00% documented

### Fixed

- `SmartMerger` now correctly handles merge conflicts that involve `kettle-dev:freeze` blocks
  - Entire freeze block from destination is preserved
  - Still allows template-only nodes to be added
  - Resolves an issue where template-only nodes were dropped if destination contained a freeze block

## [1.0.0] - 2025-12-03

- TAG: [v1.0.0][1.0.0t]
- COVERAGE: 95.44% -- 607/636 lines in 7 files
- BRANCH COVERAGE: 81.94% -- 186/227 branches in 7 files
- 100.00% documented

### Added

- Initial release

[Unreleased]: https://github.com/kettle-rb/prism-merge/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/kettle-rb/prism-merge/compare/v1.0.2...v1.0.3
[1.0.3t]: https://github.com/kettle-rb/prism-merge/releases/tag/v1.0.3
[1.0.2]: https://github.com/kettle-rb/prism-merge/compare/v1.0.1...v1.0.2
[1.0.2t]: https://github.com/kettle-rb/prism-merge/releases/tag/v1.0.2
[1.0.1]: https://github.com/kettle-rb/prism-merge/compare/v1.0.0...v1.0.1
[1.0.1t]: https://github.com/kettle-rb/prism-merge/releases/tag/v1.0.1
[1.0.0]: https://github.com/kettle-rb/prism-merge/compare/71fcddaa659cd6e9e94053e67524e5a400423ced...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/prism-merge/tags/v1.0.0
