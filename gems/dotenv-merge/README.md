[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang] [![kettle-rb Logo by Aboling0, CC BY-SA 4.0][🖼️kettle-rb-i]][🖼️kettle-rb]

[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg
[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN
[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg
[🖼️ruby-lang]: https://www.ruby-lang.org/
[🖼️kettle-rb-i]: https://logos.galtzo.com/assets/images/kettle-rb/avatar-192px.svg
[🖼️kettle-rb]: https://github.com/kettle-rb

# ☯️ Dotenv::Merge

[![Version][👽versioni]][👽version] [![GitHub tag (latest SemVer)][⛳️tag-img]][⛳️tag] [![License: AGPL-3.0-only][📄license-img]][📄license-ref] [![Downloads Rank][👽dl-ranki]][👽dl-rank] [![Open Source Helpers][👽oss-helpi]][👽oss-help] [![CodeCov Test Coverage][🏀codecovi]][🏀codecov] [![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls] [![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov] [![QLTY Maintainability][🏀qlty-mnti]][🏀qlty-mnt] [![CI Heads][🚎3-hd-wfi]][🚎3-hd-wf] [![CI Runtime Dependencies @ HEAD][🚎12-crh-wfi]][🚎12-crh-wf] [![CI Current][🚎11-c-wfi]][🚎11-c-wf] [![CI Truffle Ruby][🚎9-t-wfi]][🚎9-t-wf] [![CI JRuby][🚎10-j-wfi]][🚎10-j-wf] [![Deps Locked][🚎13-🔒️-wfi]][🚎13-🔒️-wf] [![Deps Unlocked][🚎14-🔓️-wfi]][🚎14-🔓️-wf] [![CI Test Coverage][🚎2-cov-wfi]][🚎2-cov-wf] [![CI Style][🚎5-st-wfi]][🚎5-st-wf] [![CodeQL][🖐codeQL-img]][🖐codeQL] [![Apache SkyWalking Eyes License Compatibility Check][🚎15-🪪-wfi]][🚎15-🪪-wf]

`if ci_badges.map(&:color).detect { it != "green"}` ☝️ [let me know][🖼️galtzo-discord], as I may have missed the [discord notification][🖼️galtzo-discord].

---

`if ci_badges.map(&:color).all? { it == "green"}` 👇️ send money so I can do more of this. FLOSS maintenance is now my full-time job.

[![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors] [![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]

<details>
    <summary>👣 How will this project approach the September 2025 hostile takeover of RubyGems? 🚑️</summary>

I've summarized my thoughts in [this blog post](https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo).

</details>

## 🌻 Synopsis

Dotenv::Merge is a standalone Ruby module that intelligently merges two versions of a dotenv (`.env`) file. It's like a smart "git merge" specifically designed for environment configuration files. Built on top of [ast-merge][ast-merge], it shares the same architecture as [prism-merge][prism-merge] for Ruby source files.

### Key Features

- **Dotenv-Aware**: Understands dotenv file format (KEY=value, comments, exports)
- **Intelligent**: Matches environment variables by key name
- **Comment-Preserving**: Comments and blank lines are preserved in their context
- **Freeze Block Support**: Respects freeze markers (default: `dotenv-merge:freeze` / `dotenv-merge:unfreeze`) for merge control - customizable to match your project's conventions
- **Full Provenance**: Tracks origin of every line
- **Standalone**: Minimal dependencies - just `ast-merge`
- **Customizable**:
    - `signature_generator` - callable custom signature generators
    - `preference` - setting of `:template`, `:destination`, or a Hash for per-node-type preferences
    - `node_splitter` - Hash mapping node types to callables for per-node-type merge customization (see [ast-merge][ast-merge] docs)
    - `add_template_only_nodes` - setting to retain variables that do not exist in destination
    - `freeze_token` - customize freeze block markers (default: `"dotenv-merge"`)

### Supported Line Types

| Line Type | Format | Matching Behavior |
| --- | --- | --- |
| Assignment | `KEY=value` | Variables match by key name |
| Export | `export KEY=value` | Treated as assignment with export flag |
| Comment | `# comment text` | Preserved in context |
| Blank | (empty line) | Preserved for readability |
| Double-quoted | `KEY="value with\nescapes"` | Escape sequences processed |
| Single-quoted | `KEY='literal value'` | No escape processing |
| Inline comment | `KEY=value # comment` | Comment stripped from value |

### Example

```ruby
require "dotenv/merge"

template = File.read("template.env")
destination = File.read("destination.env")

merger = Dotenv::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.env", result.to_s)
```

### The `*-merge` Gem Family

The `*-merge` gem family provides intelligent, AST-based merging for various file formats. At the foundation is [tree_haver][tree_haver], which provides a unified cross-Ruby parsing API that works seamlessly across MRI, JRuby, and TruffleRuby.

| Gem                                      |                                                         Version / CI                                                         | Language<br>/ Format | Parser Backend(s)                                                                                     | Description                                                                      |
|------------------------------------------|:----------------------------------------------------------------------------------------------------------------------------:|----------------------|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| [tree_haver][tree_haver]                 |                 [![Version][tree_haver-gem-i]][tree_haver-gem] <br/> [![CI][tree_haver-ci-i]][tree_haver-ci]                 | Multi                | Supported Backends: MRI C, Rust, FFI, Java, Prism, Psych, Commonmarker, Markly, Citrus, Parslet       | **Foundation**: Cross-Ruby adapter for parsing libraries (like Faraday for HTTP) |
| [ast-merge][ast-merge]                   |                   [![Version][ast-merge-gem-i]][ast-merge-gem] <br/> [![CI][ast-merge-ci-i]][ast-merge-ci]                   | Text                 | internal                                                                                              | **Infrastructure**: Shared base classes and merge logic for all `*-merge` gems   |
| [bash-merge][bash-merge]                 |                 [![Version][bash-merge-gem-i]][bash-merge-gem] <br/> [![CI][bash-merge-ci-i]][bash-merge-ci]                 | Bash                 | [tree-sitter-bash][ts-bash] (via tree_haver)                                                          | Smart merge for Bash scripts                                                     |
| [commonmarker-merge][commonmarker-merge] | [![Version][commonmarker-merge-gem-i]][commonmarker-merge-gem] <br/> [![CI][commonmarker-merge-ci-i]][commonmarker-merge-ci] | Markdown             | [Commonmarker][commonmarker] (via tree_haver)                                                         | Smart merge for Markdown (CommonMark via comrak Rust)                            |
| [dotenv-merge][dotenv-merge]             |             [![Version][dotenv-merge-gem-i]][dotenv-merge-gem] <br/> [![CI][dotenv-merge-ci-i]][dotenv-merge-ci]             | Dotenv               | internal                                                                                              | Smart merge for `.env` files                                                     |
| [json-merge][json-merge]                 |                 [![Version][json-merge-gem-i]][json-merge-gem] <br/> [![CI][json-merge-ci-i]][json-merge-ci]                 | JSON                 | [tree-sitter-json][ts-json] (via tree_haver)                                                          | Smart merge for JSON files                                                       |
| [jsonc-merge][jsonc-merge]               |               [![Version][jsonc-merge-gem-i]][jsonc-merge-gem] <br/> [![CI][jsonc-merge-ci-i]][jsonc-merge-ci]               | JSONC                | [tree-sitter-jsonc][ts-jsonc] (via tree_haver)                                                        | ⚠️ Proof of concept; Smart merge for JSON with Comments                          |
| [markdown-merge][markdown-merge]         |         [![Version][markdown-merge-gem-i]][markdown-merge-gem] <br/> [![CI][markdown-merge-ci-i]][markdown-merge-ci]         | Markdown             | [Commonmarker][commonmarker] / [Markly][markly] (via tree_haver), [Parslet][parslet]                  | **Foundation**: Shared base for Markdown mergers with inner code block merging   |
| [markly-merge][markly-merge]             |             [![Version][markly-merge-gem-i]][markly-merge-gem] <br/> [![CI][markly-merge-ci-i]][markly-merge-ci]             | Markdown             | [Markly][markly] (via tree_haver)                                                                     | Smart merge for Markdown (CommonMark via cmark-gfm C)                            |
| [prism-merge][prism-merge]               |               [![Version][prism-merge-gem-i]][prism-merge-gem] <br/> [![CI][prism-merge-ci-i]][prism-merge-ci]               | Ruby                 | [Prism][prism] (`prism` std lib gem)                                                                  | Smart merge for Ruby source files                                                |
| [psych-merge][psych-merge]               |               [![Version][psych-merge-gem-i]][psych-merge-gem] <br/> [![CI][psych-merge-ci-i]][psych-merge-ci]               | YAML                 | [Psych][psych] (`psych` std lib gem)                                                                  | Smart merge for YAML files                                                       |
| [rbs-merge][rbs-merge]                   |                   [![Version][rbs-merge-gem-i]][rbs-merge-gem] <br/> [![CI][rbs-merge-ci-i]][rbs-merge-ci]                   | RBS                  | [tree-sitter-rbs][ts-rbs] (via tree_haver), [RBS][rbs] (`rbs` std lib gem)                            | Smart merge for Ruby type signatures                                             |
| [toml-merge][toml-merge]                 |                 [![Version][toml-merge-gem-i]][toml-merge-gem] <br/> [![CI][toml-merge-ci-i]][toml-merge-ci]                 | TOML                 | [Parslet + toml][toml], [Citrus + toml-rb][toml-rb], [tree-sitter-toml][ts-toml] (all via tree_haver) | Smart merge for TOML files                                                       |

#### Backend Platform Compatibility

tree_haver supports multiple parsing backends, but not all backends work on all Ruby platforms:

| Platform 👉️<br> TreeHaver Backend 👇️          | MRI | JRuby | TruffleRuby | Notes                                                                      |
|-------------------------------------------------|:---:|:-----:|:-----------:|----------------------------------------------------------------------------|
| **MRI** ([ruby_tree_sitter][ruby_tree_sitter])  |  ✅  |   ❌   |      ❌      | C extension, MRI only                                                      |
| **Rust** ([tree_stump][tree_stump])             |  ✅  |   ❌   |      ❌      | Rust extension via magnus/rb-sys, MRI only                                 |
| **FFI** ([ffi][ffi])                            |  ✅  |   ✅   |      ❌      | TruffleRuby's FFI doesn't support `STRUCT_BY_VALUE`                        |
| **Java** ([jtreesitter][jtreesitter])           |  ❌  |   ✅   |      ❌      | JRuby only, requires grammar JARs                                          |
| **Prism** ([prism][prism])                      |  ✅  |   ✅   |      ✅      | Ruby parsing, stdlib in Ruby 3.4+                                          |
| **Psych** ([psych][psych])                      |  ✅  |   ✅   |      ✅      | YAML parsing, stdlib                                                       |
| **Citrus** ([citrus][citrus])                   |  ✅  |   ✅   |      ✅      | Pure Ruby PEG parser, no native dependencies                               |
| **Parslet** ([parslet][parslet])                |  ✅  |   ✅   |      ✅      | Pure Ruby PEG parser, no native dependencies                               |
| **Commonmarker** ([commonmarker][commonmarker]) |  ✅  |   ❌   |      ❓      | Rust extension for Markdown (via [commonmarker-merge][commonmarker-merge]) |
| **Markly** ([markly][markly])                   |  ✅  |   ❌   |      ❓      | C extension for Markdown  (via [markly-merge][markly-merge])               |

**Legend**: ✅ = Works, ❌ = Does not work, ❓ = Untested

**Why some backends don't work on certain platforms**:

- **JRuby**: Runs on the JVM; cannot load native C/Rust extensions (`.so` files)
- **TruffleRuby**: Has C API emulation via Sulong/LLVM, but it doesn't expose all MRI internals that native extensions require (e.g., `RBasic.flags`, `rb_gc_writebarrier`)
- **FFI on TruffleRuby**: TruffleRuby's FFI implementation doesn't support returning structs by value, which tree-sitter's C API requires

**Example implementations** for the gem templating use case:

| Gem                      | Purpose         | Description                                   |
|--------------------------|-----------------|-----------------------------------------------|
| [kettle-dev][kettle-dev] | Gem Development | Gem templating tool using `*-merge` gems      |
| [kettle-jem][kettle-jem] | Gem Templating  | Gem template library with smart merge support |

[tree_haver]: https://github.com/kettle-rb/tree_haver
[ast-merge]: https://github.com/kettle-rb/ast-merge
[prism-merge]: https://github.com/kettle-rb/prism-merge
[psych-merge]: https://github.com/kettle-rb/psych-merge
[json-merge]: https://github.com/kettle-rb/json-merge
[jsonc-merge]: https://github.com/kettle-rb/jsonc-merge
[bash-merge]: https://github.com/kettle-rb/bash-merge
[rbs-merge]: https://github.com/kettle-rb/rbs-merge
[dotenv-merge]: https://github.com/kettle-rb/dotenv-merge
[toml-merge]: https://github.com/kettle-rb/toml-merge
[markdown-merge]: https://github.com/kettle-rb/markdown-merge
[markly-merge]: https://github.com/kettle-rb/markly-merge
[commonmarker-merge]: https://github.com/kettle-rb/commonmarker-merge
[kettle-dev]: https://github.com/kettle-rb/kettle-dev
[kettle-jem]: https://github.com/kettle-rb/kettle-jem
[tree_haver-gem]: https://bestgems.org/gems/tree_haver
[ast-merge-gem]: https://bestgems.org/gems/ast-merge
[prism-merge-gem]: https://bestgems.org/gems/prism-merge
[psych-merge-gem]: https://bestgems.org/gems/psych-merge
[json-merge-gem]: https://bestgems.org/gems/json-merge
[jsonc-merge-gem]: https://bestgems.org/gems/jsonc-merge
[bash-merge-gem]: https://bestgems.org/gems/bash-merge
[rbs-merge-gem]: https://bestgems.org/gems/rbs-merge
[dotenv-merge-gem]: https://bestgems.org/gems/dotenv-merge
[toml-merge-gem]: https://bestgems.org/gems/toml-merge
[markdown-merge-gem]: https://bestgems.org/gems/markdown-merge
[markly-merge-gem]: https://bestgems.org/gems/markly-merge
[commonmarker-merge-gem]: https://bestgems.org/gems/commonmarker-merge
[kettle-dev-gem]: https://bestgems.org/gems/kettle-dev
[kettle-jem-gem]: https://bestgems.org/gems/kettle-jem
[tree_haver-gem-i]: https://img.shields.io/gem/v/tree_haver.svg
[ast-merge-gem-i]: https://img.shields.io/gem/v/ast-merge.svg
[prism-merge-gem-i]: https://img.shields.io/gem/v/prism-merge.svg
[psych-merge-gem-i]: https://img.shields.io/gem/v/psych-merge.svg
[json-merge-gem-i]: https://img.shields.io/gem/v/json-merge.svg
[jsonc-merge-gem-i]: https://img.shields.io/gem/v/jsonc-merge.svg
[bash-merge-gem-i]: https://img.shields.io/gem/v/bash-merge.svg
[rbs-merge-gem-i]: https://img.shields.io/gem/v/rbs-merge.svg
[dotenv-merge-gem-i]: https://img.shields.io/gem/v/dotenv-merge.svg
[toml-merge-gem-i]: https://img.shields.io/gem/v/toml-merge.svg
[markdown-merge-gem-i]: https://img.shields.io/gem/v/markdown-merge.svg
[markly-merge-gem-i]: https://img.shields.io/gem/v/markly-merge.svg
[commonmarker-merge-gem-i]: https://img.shields.io/gem/v/commonmarker-merge.svg
[kettle-dev-gem-i]: https://img.shields.io/gem/v/kettle-dev.svg
[kettle-jem-gem-i]: https://img.shields.io/gem/v/kettle-jem.svg
[tree_haver-ci-i]: https://github.com/kettle-rb/tree_haver/actions/workflows/current.yml/badge.svg
[ast-merge-ci-i]: https://github.com/kettle-rb/ast-merge/actions/workflows/current.yml/badge.svg
[prism-merge-ci-i]: https://github.com/kettle-rb/prism-merge/actions/workflows/current.yml/badge.svg
[psych-merge-ci-i]: https://github.com/kettle-rb/psych-merge/actions/workflows/current.yml/badge.svg
[json-merge-ci-i]: https://github.com/kettle-rb/json-merge/actions/workflows/current.yml/badge.svg
[jsonc-merge-ci-i]: https://github.com/kettle-rb/jsonc-merge/actions/workflows/current.yml/badge.svg
[bash-merge-ci-i]: https://github.com/kettle-rb/bash-merge/actions/workflows/current.yml/badge.svg
[rbs-merge-ci-i]: https://github.com/kettle-rb/rbs-merge/actions/workflows/current.yml/badge.svg
[dotenv-merge-ci-i]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/current.yml/badge.svg
[toml-merge-ci-i]: https://github.com/kettle-rb/toml-merge/actions/workflows/current.yml/badge.svg
[markdown-merge-ci-i]: https://github.com/kettle-rb/markdown-merge/actions/workflows/current.yml/badge.svg
[markly-merge-ci-i]: https://github.com/kettle-rb/markly-merge/actions/workflows/current.yml/badge.svg
[commonmarker-merge-ci-i]: https://github.com/kettle-rb/commonmarker-merge/actions/workflows/current.yml/badge.svg
[kettle-dev-ci-i]: https://github.com/kettle-rb/kettle-dev/actions/workflows/current.yml/badge.svg
[kettle-jem-ci-i]: https://github.com/kettle-rb/kettle-jem/actions/workflows/current.yml/badge.svg
[tree_haver-ci]: https://github.com/kettle-rb/tree_haver/actions/workflows/current.yml
[ast-merge-ci]: https://github.com/kettle-rb/ast-merge/actions/workflows/current.yml
[prism-merge-ci]: https://github.com/kettle-rb/prism-merge/actions/workflows/current.yml
[psych-merge-ci]: https://github.com/kettle-rb/psych-merge/actions/workflows/current.yml
[json-merge-ci]: https://github.com/kettle-rb/json-merge/actions/workflows/current.yml
[jsonc-merge-ci]: https://github.com/kettle-rb/jsonc-merge/actions/workflows/current.yml
[bash-merge-ci]: https://github.com/kettle-rb/bash-merge/actions/workflows/current.yml
[rbs-merge-ci]: https://github.com/kettle-rb/rbs-merge/actions/workflows/current.yml
[dotenv-merge-ci]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/current.yml
[toml-merge-ci]: https://github.com/kettle-rb/toml-merge/actions/workflows/current.yml
[markdown-merge-ci]: https://github.com/kettle-rb/markdown-merge/actions/workflows/current.yml
[markly-merge-ci]: https://github.com/kettle-rb/markly-merge/actions/workflows/current.yml
[commonmarker-merge-ci]: https://github.com/kettle-rb/commonmarker-merge/actions/workflows/current.yml
[kettle-dev-ci]: https://github.com/kettle-rb/kettle-dev/actions/workflows/current.yml
[kettle-jem-ci]: https://github.com/kettle-rb/kettle-jem/actions/workflows/current.yml
[prism]: https://github.com/ruby/prism
[psych]: https://github.com/ruby/psych
[ffi]: https://github.com/ffi/ffi
[ts-json]: https://github.com/tree-sitter/tree-sitter-json
[ts-jsonc]: https://gitlab.com/WhyNotHugo/tree-sitter-jsonc
[ts-bash]: https://github.com/tree-sitter/tree-sitter-bash
[ts-rbs]: https://github.com/joker1007/tree-sitter-rbs
[ts-toml]: https://github.com/tree-sitter-grammars/tree-sitter-toml
[dotenv]: https://github.com/bkeepers/dotenv
[rbs]: https://github.com/ruby/rbs
[toml-rb]: https://github.com/emancu/toml-rb
[toml]: https://github.com/jm/toml
[markly]: https://github.com/ioquatix/markly
[commonmarker]: https://github.com/gjtorikian/commonmarker
[ruby_tree_sitter]: https://github.com/Faveod/ruby-tree-sitter
[tree_stump]: https://github.com/joker1007/tree_stump
[jtreesitter]: https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter
[citrus]: https://github.com/mjackson/citrus
[parslet]: https://github.com/kschiess/parslet

## 💡 Info you can shake a stick at

| Tokens to Remember      | [![Gem name][⛳️name-img]][⛳️gem-name] [![Gem namespace][⛳️namespace-img]][⛳️gem-namespace]                                                                                                                                                                                                                                                                          |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Works with JRuby        | [![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf] [![JRuby HEAD Compat][💎jruby-headi]][🚎3-hd-wf]|
| Works with Truffle Ruby | [![Truffle Ruby 24.2 Compat][💎truby-24.2i]][🚎truby-24.2-wf] [![Truffle Ruby 25.0 Compat][💎truby-25.0i]][🚎truby-25.0-wf] [![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf]|
| Works with MRI Ruby 4   | [![Ruby 4.0 Compat][💎ruby-4.0i]][🚎11-c-wf] [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf] [![Ruby HEAD Compat][💎ruby-headi]][🚎3-hd-wf]|
| Works with MRI Ruby 3   | [![Ruby 3.2 Compat][💎ruby-3.2i]][🚎ruby-3.2-wf] [![Ruby 3.3 Compat][💎ruby-3.3i]][🚎ruby-3.3-wf] [![Ruby 3.4 Compat][💎ruby-3.4i]][🚎ruby-3.4-wf]|
| Support & Community     | [![Join Me on Daily.dev's RubyFriends][✉️ruby-friends-img]][✉️ruby-friends] [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite] [![Get help from me on Upwork][👨🏼‍🏫expsup-upwork-img]][👨🏼‍🏫expsup-upwork] [![Get help from me on Codementor][👨🏼‍🏫expsup-codementor-img]][👨🏼‍🏫expsup-codementor]                                       |
| Source                  | [![Source on GitLab.com][📜src-gl-img]][📜src-gl] [![Source on CodeBerg.org][📜src-cb-img]][📜src-cb] [![Source on Github.com][📜src-gh-img]][📜src-gh] [![The best SHA: dQw4w9WgXcQ!][🧮kloc-img]][🧮kloc]                                                                                                                                                         |
| Documentation           | [![Current release on RubyDoc.info][📜docs-cr-rd-img]][🚎yard-current] [![YARD on Galtzo.com][📜docs-head-rd-img]][🚎yard-head] [![Maintainer Blog][🚂maint-blog-img]][🚂maint-blog] [![GitLab Wiki][📜gl-wiki-img]][📜gl-wiki] [![GitHub Wiki][📜gh-wiki-img]][📜gh-wiki]                                                                                          |
| Compliance              | [![License: AGPL-3.0-only][📄license-img]][📄license-ref] [![Apache license compatibility: Category X][📄license-compat-img]][📄license-compat] [![📄ilo-declaration-img]][📄ilo-declaration] [![Security Policy][🔐security-img]][🔐security] [![Contributor Covenant 2.1][🪇conduct-img]][🪇conduct] [![SemVer 2.0.0][📌semver-img]][📌semver] |
| Style                   | [![Enforced Code Style Linter][💎rlts-img]][💎rlts] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog] [![Gitmoji Commits][📌gitmoji-img]][📌gitmoji] [![Compatibility appraised by: appraisal2][💎appraisal2-img]][💎appraisal2]                                                                                                                  |
| Maintainer 🎖️          | [![Follow Me on LinkedIn][💖🖇linkedin-img]][💖🖇linkedin] [![Follow Me on Ruby.Social][💖🐘ruby-mast-img]][💖🐘ruby-mast] [![Follow Me on Bluesky][💖🦋bluesky-img]][💖🦋bluesky] [![Contact Maintainer][🚂maint-contact-img]][🚂maint-contact] [![My technical writing][💖💁🏼‍♂️devto-img]][💖💁🏼‍♂️devto]                                                      |
| `...` 💖                | [![Find Me on WellFound:][💖✌️wellfound-img]][💖✌️wellfound] [![Find Me on CrunchBase][💖💲crunchbase-img]][💖💲crunchbase] [![My LinkTree][💖🌳linktree-img]][💖🌳linktree] [![More About Me][💖💁🏼‍♂️aboutme-img]][💖💁🏼‍♂️aboutme] [🧊][💖🧊berg] [🐙][💖🐙hub]  [🛖][💖🛖hut] [🧪][💖🧪lab]                                                                   |

### Compatibility

Compatible with MRI Ruby 3.2.0+, and concordant releases of JRuby, and TruffleRuby.

| 🚚 _Amazing_ test matrix was brought to you by | 🔎 appraisal2 🔎 and the color 💚 green 💚             |
|------------------------------------------------|--------------------------------------------------------|
| 👟 Check it out!                               | ✨ [github.com/appraisal-rb/appraisal2][💎appraisal2] ✨ |

### Federated DVCS

<details markdown="1">
  <summary>Find this repo on federated forges (Coming soon!)</summary>

| Federated [DVCS][💎d-in-dvcs] Repository        | Status                                                                | Issues                    | PRs                      | Wiki                      | CI                       | Discussions                  |
|-------------------------------------------------|-----------------------------------------------------------------------|---------------------------|--------------------------|---------------------------|--------------------------|------------------------------|
| 🧪 [kettle-rb/dotenv-merge on GitLab][📜src-gl]   | The Truth                                                             | [💚][🤝gl-issues]         | [💚][🤝gl-pulls]         | [💚][📜gl-wiki]           | 🐭 Tiny Matrix           | ➖                            |
| 🧊 [kettle-rb/dotenv-merge on CodeBerg][📜src-cb] | An Ethical Mirror ([Donate][🤝cb-donate])                             | [💚][🤝cb-issues]         | [💚][🤝cb-pulls]         | ➖                         | ⭕️ No Matrix             | ➖                            |
| 🐙 [kettle-rb/dotenv-merge on GitHub][📜src-gh]   | Another Mirror                                                        | [💚][🤝gh-issues]         | [💚][🤝gh-pulls]         | [💚][📜gh-wiki]           | 💯 Full Matrix           | [💚][gh-discussions]         |
| 🎮️ [Discord Server][✉️discord-invite]          | [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite] | [Let's][✉️discord-invite] | [talk][✉️discord-invite] | [about][✉️discord-invite] | [this][✉️discord-invite] | [library!][✉️discord-invite] |

</details>

[gh-discussions]: https://github.com/kettle-rb/dotenv-merge/discussions

### Enterprise Support [![Tidelift](https://tidelift.com/badges/package/rubygems/dotenv-merge)](https://tidelift.com/subscription/pkg/rubygems-dotenv-merge?utm_source=rubygems-dotenv-merge&utm_medium=referral&utm_campaign=readme)

Available as part of the Tidelift Subscription.

<details markdown="1">
  <summary>Need enterprise-level guarantees?</summary>

The maintainers of this and thousands of other packages are working with Tidelift to deliver commercial support and maintenance for the open source packages you use to build your applications. Save time, reduce risk, and improve code health, while paying the maintainers of the exact packages you use.

[![Get help from me on Tidelift][🏙️entsup-tidelift-img]][🏙️entsup-tidelift]

- 💡Subscribe for support guarantees covering _all_ your FLOSS dependencies
- 💡Tidelift is part of [Sonar][🏙️entsup-tidelift-sonar]
- 💡Tidelift pays maintainers to maintain the software you depend on!<br/>📊`@`Pointy Haired Boss: An [enterprise support][🏙️entsup-tidelift] subscription is "[never gonna let you down][🧮kloc]", and *supports* open source maintainers

Alternatively:

- [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite]
- [![Get help from me on Upwork][👨🏼‍🏫expsup-upwork-img]][👨🏼‍🏫expsup-upwork]
- [![Get help from me on Codementor][👨🏼‍🏫expsup-codementor-img]][👨🏼‍🏫expsup-codementor]

</details>

## ✨ Installation

Install the gem and add to the application's Gemfile by executing:

```console
bundle add dotenv-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install dotenv-merge
```

### 🔒 Secure Installation

<details markdown="1">
  <summary>For Medium or High Security Installations</summary>

This gem is cryptographically signed and has verifiable [SHA-256 and SHA-512][💎SHA_checksums] checksums by
[stone_checksums][💎stone_checksums]. Be sure the gem you install hasn’t been tampered with
by following the instructions below.

Add my public key (if you haven’t already; key expires 2045-04-29) as a trusted certificate:

```console
gem cert --add <(curl -Ls https://raw.github.com/galtzo-floss/certs/main/pboling.pem)
```

You only need to do that once.  Then proceed to install with:

```console
gem install dotenv-merge -P HighSecurity
```

The `HighSecurity` trust profile will verify signed gems, and not allow the installation of unsigned dependencies.

If you want to up your security game full-time:

```console
bundle config set --global trust-policy MediumSecurity
```

`MediumSecurity` instead of `HighSecurity` is necessary if not all the gems you use are signed.

NOTE: Be prepared to track down certs for signed gems and add them the same way you added mine.

</details>

## ⚙️ Configuration

```ruby
merger = Dotenv::Merge::SmartMerger.new(
  template,
  destination,
  # When conflicts occur, prefer template or destination values
  preference: :template,            # or :destination (default)
  # Add entries that only exist in template
  add_template_only_nodes: true,    # default: false
)
```

### Signature Match Preference

Control which source wins when both files have the same key:

- **`:template`** - Template values replace destination values

    - Version files (`VERSION=2.0.0` should replace `VERSION=1.0.0`)
    - API endpoint updates (`API_URL=https://new-api.example.com`)

- **`:destination`** (default) - Destination values are preserved

    - Local development settings
    - Project-specific customizations

### Template-Only Nodes

Control whether to add entries that only exist in the template:

- **`true`** - Add new entries from template

    - New required environment variables
    - New configuration options

- **`false`** (default) - Skip template-only entries

    - Template has placeholder values
    - Destination is authoritative

## 🔧 Basic Usage

### Simple Merge

```ruby
require "dotenv/merge"

template = File.read("template.env")
destination = File.read("destination.env")

merger = Dotenv::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.env", result)
```

### Working with Freeze Blocks

Freeze blocks protect sections of your `.env` file from being modified during merges:

    # << FREEZE: project_secrets
    DATABASE_URL=postgresql://localhost/myapp_dev
    SECRET_KEY_BASE=my_local_secret_key_value
    # >> FREEZE: project_secrets

    # These entries can be updated by template
    API_VERSION=v2

### Adding Template-Only Entries

```ruby
# Template introduces a new required variable
template = <<~ENV
  DATABASE_URL=postgresql://localhost/template_db
  NEW_FEATURE_FLAG=enabled
ENV

destination = <<~ENV
  DATABASE_URL=postgresql://localhost/myapp_dev
ENV

merger = Dotenv::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: true,
)
result = merger.merge
# Result includes DATABASE_URL from destination + NEW_FEATURE_FLAG from template
```

## 🦷 FLOSS Funding

While kettle-rb tools are free software and will always be, the project would benefit immensely from some funding.
Raising a monthly budget of... "dollars" would make the project more sustainable.

We welcome both individual and corporate sponsors! We also offer a
wide array of funding channels to account for your preferences
(although currently [Open Collective][🖇osc] is our preferred funding platform).

**If you're working in a company that's making significant use of kettle-rb tools we'd
appreciate it if you suggest to your company to become a kettle-rb sponsor.**

You can support the development of kettle-rb tools via
[GitHub Sponsors][🖇sponsor],
[Liberapay][⛳liberapay],
[PayPal][🖇paypal],
[Open Collective][🖇osc]
and [Tidelift][🏙️entsup-tidelift].

| 📍 NOTE                                                                                                                                                                                                              |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| If doing a sponsorship in the form of donation is problematic for your company <br/> from an accounting standpoint, we'd recommend the use of Tidelift, <br/> where you can get a support-like subscription instead. |

### Open Collective for Individuals

Support us with a monthly donation and help us continue our activities. [[Become a backer](https://opencollective.com/kettle-rb#backer)]

NOTE: [kettle-readme-backers][kettle-readme-backers] updates this list every day, automatically.

<!-- OPENCOLLECTIVE-INDIVIDUALS:START -->
No backers yet. Be the first!
<!-- OPENCOLLECTIVE-INDIVIDUALS:END -->

### Open Collective for Organizations

Become a sponsor and get your logo on our README on GitHub with a link to your site. [[Become a sponsor](https://opencollective.com/kettle-rb#sponsor)]

NOTE: [kettle-readme-backers][kettle-readme-backers] updates this list every day, automatically.

<!-- OPENCOLLECTIVE-ORGANIZATIONS:START -->
No sponsors yet. Be the first!
<!-- OPENCOLLECTIVE-ORGANIZATIONS:END -->

[kettle-readme-backers]: https://github.com/kettle-rb/dotenv-merge/blob/main/exe/kettle-readme-backers

### Another way to support open-source

I’m driven by a passion to foster a thriving open-source community – a space where people can tackle complex problems, no matter how small.  Revitalizing libraries that have fallen into disrepair, and building new libraries focused on solving real-world challenges, are my passions.  I was recently affected by layoffs, and the tech jobs market is unwelcoming. I’m reaching out here because your support would significantly aid my efforts to provide for my family, and my farm (11 🐔 chickens, 2 🐶 dogs, 3 🐰 rabbits, 8 🐈‍ cats).

If you work at a company that uses my work, please encourage them to support me as a corporate sponsor. My work on gems you use might show up in `bundle fund`.

I’m developing a new library, [floss_funding][🖇floss-funding-gem], designed to empower open-source developers like myself to get paid for the work we do, in a sustainable way. Please give it a look.

**[Floss-Funding.dev][🖇floss-funding.dev]: 👉️ No network calls. 👉️ No tracking. 👉️ No oversight. 👉️ Minimal crypto hashing. 💡 Easily disabled nags**

[![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors] [![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate to my FLOSS efforts at ko-fi.com][🖇kofi-img]][🖇kofi] [![Donate to my FLOSS efforts using Patreon][🖇patreon-img]][🖇patreon]

## 🔐 Security

See [SECURITY.md][🔐security].

## 🤝 Contributing

If you need some ideas of where to help, you could work on adding more code coverage,
or if it is already 💯 (see [below](#code-coverage)) check [issues][🤝gh-issues] or [PRs][🤝gh-pulls],
or use the gem and think about how it could be better.

We [![Keep A Changelog][📗keep-changelog-img]][📗keep-changelog] so if you make changes, remember to update it.

See [CONTRIBUTING.md][🤝contributing] for more detailed instructions.

### 🚀 Release Instructions

See [CONTRIBUTING.md][🤝contributing].

### Code Coverage

[![Coverage Graph][🏀codecov-g]][🏀codecov]

[![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls]

[![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov]

### 🪇 Code of Conduct

Everyone interacting with this project's codebases, issue trackers,
chat rooms and mailing lists agrees to follow the [![Contributor Covenant 2.1][🪇conduct-img]][🪇conduct].

## 🌈 Contributors

[![Contributors][🖐contributors-img]][🖐contributors]

Made with [contributors-img][🖐contrib-rocks].

Also see GitLab Contributors: [https://gitlab.com/kettle-rb/dotenv-merge/-/graphs/main][🚎contributors-gl]

<details>
    <summary>⭐️ Star History</summary>

<a href="https://star-history.com/#kettle-rb/dotenv-merge&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=kettle-rb/dotenv-merge&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=kettle-rb/dotenv-merge&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=kettle-rb/dotenv-merge&type=Date" />
 </picture>
</a>

</details>

## 📌 Versioning

This Library adheres to [![Semantic Versioning 2.0.0][📌semver-img]][📌semver].
Violations of this scheme should be reported as bugs.
Specifically, if a minor or patch version is released that breaks backward compatibility,
a new version should be immediately released that restores compatibility.
Breaking changes to the public API will only be introduced with new major versions.

> dropping support for a platform is both obviously and objectively a breaking change <br/>
>—Jordan Harband ([@ljharb](https://github.com/ljharb), maintainer of SemVer) [in SemVer issue 716][📌semver-breaking]

I understand that policy doesn't work universally ("exceptions to every rule!"),
but it is the policy here.
As such, in many cases it is good to specify a dependency on this library using
the [Pessimistic Version Constraint][📌pvc] with two digits of precision.

For example:

```ruby
spec.add_dependency("dotenv-merge", "~> 2.0")
```

<details markdown="1">
<summary>📌 Is "Platform Support" part of the public API? More details inside.</summary>

SemVer should, IMO, but doesn't explicitly, say that dropping support for specific Platforms
is a *breaking change* to an API, and for that reason the bike shedding is endless.

To get a better understanding of how SemVer is intended to work over a project's lifetime,
read this article from the creator of SemVer:

- ["Major Version Numbers are Not Sacred"][📌major-versions-not-sacred]

</details>

See [CHANGELOG.md][📌changelog] for a list of releases.

## 📄 License

The gem is available under the following license: [AGPL-3.0-only](AGPL-3.0-only.md).
See [LICENSE.md][📄license] for details.

If none of the available licenses suit your use case, please [contact us](mailto:floss@galtzo.com) to discuss a custom commercial license.

### © Copyright

See [LICENSE.md][📄license] for the official copyright notice.

## 🤑 A request for help

Maintainers have teeth and need to pay their dentists.
After getting laid off in an RIF in March, and encountering difficulty finding a new one,
I began spending most of my time building open source tools.
I'm hoping to be able to pay for my kids' health insurance this month,
so if you value the work I am doing, I need your support.
Please consider sponsoring me or the project.

To join the community or get help 👇️ Join the Discord.

[![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite]

To say "thanks!" ☝️ Join the Discord or 👇️ send money.

[![Sponsor kettle-rb/dotenv-merge on Open Source Collective][🖇osc-all-bottom-img]][🖇osc] 💌 [![Sponsor me on GitHub Sponsors][🖇sponsor-bottom-img]][🖇sponsor] 💌 [![Sponsor me on Liberapay][⛳liberapay-bottom-img]][⛳liberapay] 💌 [![Donate on PayPal][🖇paypal-bottom-img]][🖇paypal]

### Please give the project a star ⭐ ♥.

Thanks for RTFM. ☺️

[⛳liberapay-img]: https://img.shields.io/liberapay/goal/pboling.svg?logo=liberapay&color=a51611&style=flat
[⛳liberapay-bottom-img]: https://img.shields.io/liberapay/goal/pboling.svg?style=for-the-badge&logo=liberapay&color=a51611
[⛳liberapay]: https://liberapay.com/pboling/donate
[🖇osc-all-img]: https://img.shields.io/opencollective/all/kettle-rb
[🖇osc-sponsors-img]: https://img.shields.io/opencollective/sponsors/kettle-rb
[🖇osc-backers-img]: https://img.shields.io/opencollective/backers/kettle-rb
[🖇osc-backers]: https://opencollective.com/kettle-rb#backer
[🖇osc-backers-i]: https://opencollective.com/kettle-rb/backers/badge.svg?style=flat
[🖇osc-sponsors]: https://opencollective.com/kettle-rb#sponsor
[🖇osc-sponsors-i]: https://opencollective.com/kettle-rb/sponsors/badge.svg?style=flat
[🖇osc-all-bottom-img]: https://img.shields.io/opencollective/all/kettle-rb?style=for-the-badge
[🖇osc-sponsors-bottom-img]: https://img.shields.io/opencollective/sponsors/kettle-rb?style=for-the-badge
[🖇osc-backers-bottom-img]: https://img.shields.io/opencollective/backers/kettle-rb?style=for-the-badge
[🖇osc]: https://opencollective.com/kettle-rb
[🖇sponsor-img]: https://img.shields.io/badge/Sponsor_Me!-pboling.svg?style=social&logo=github
[🖇sponsor-bottom-img]: https://img.shields.io/badge/Sponsor_Me!-pboling-blue?style=for-the-badge&logo=github
[🖇sponsor]: https://github.com/sponsors/pboling
[🖇polar-img]: https://img.shields.io/badge/polar-donate-a51611.svg?style=flat
[🖇polar]: https://polar.sh/pboling
[🖇kofi-img]: https://img.shields.io/badge/ko--fi-%E2%9C%93-a51611.svg?style=flat
[🖇kofi]: https://ko-fi.com/pboling
[🖇patreon-img]: https://img.shields.io/badge/patreon-donate-a51611.svg?style=flat
[🖇patreon]: https://patreon.com/galtzo
[🖇buyme-small-img]: https://img.shields.io/badge/buy_me_a_coffee-%E2%9C%93-a51611.svg?style=flat
[🖇buyme-img]: https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20latte&emoji=&slug=pboling&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff
[🖇buyme]: https://www.buymeacoffee.com/pboling
[🖇paypal-img]: https://img.shields.io/badge/donate-paypal-a51611.svg?style=flat&logo=paypal
[🖇paypal-bottom-img]: https://img.shields.io/badge/donate-paypal-a51611.svg?style=for-the-badge&logo=paypal&color=0A0A0A
[🖇paypal]: https://www.paypal.com/paypalme/peterboling
[🖇floss-funding.dev]: https://floss-funding.dev
[🖇floss-funding-gem]: https://github.com/galtzo-floss/floss_funding
[✉️discord-invite]: https://discord.gg/3qme4XHNKN
[✉️discord-invite-img-ftb]: https://img.shields.io/discord/1373797679469170758?style=for-the-badge&logo=discord
[✉️ruby-friends-img]: https://img.shields.io/badge/daily.dev-%F0%9F%92%8E_Ruby_Friends-0A0A0A?style=for-the-badge&logo=dailydotdev&logoColor=white
[✉️ruby-friends]: https://app.daily.dev/squads/rubyfriends

[✇bundle-group-pattern]: https://gist.github.com/pboling/4564780
[⛳️gem-namespace]: https://github.com/kettle-rb/dotenv-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Dotenv::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://bestgems.org/gems/dotenv-merge
[⛳️name-img]: https://img.shields.io/badge/name-dotenv--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/kettle-rb/dotenv-merge.svg
[⛳️tag]: http://github.com/kettle-rb/dotenv-merge/releases
[🚂maint-blog]: http://www.railsbling.com/tags/dotenv-merge
[🚂maint-blog-img]: https://img.shields.io/badge/blog-railsbling-0093D0.svg?style=for-the-badge&logo=rubyonrails&logoColor=orange
[🚂maint-contact]: http://www.railsbling.com/contact
[🚂maint-contact-img]: https://img.shields.io/badge/Contact-Maintainer-0093D0.svg?style=flat&logo=rubyonrails&logoColor=red
[💖🖇linkedin]: http://www.linkedin.com/in/peterboling
[💖🖇linkedin-img]: https://img.shields.io/badge/LinkedIn-Profile-0B66C2?style=flat&logo=newjapanprowrestling
[💖✌️wellfound]: https://wellfound.com/u/peter-boling
[💖✌️wellfound-img]: https://img.shields.io/badge/peter--boling-orange?style=flat&logo=wellfound
[💖💲crunchbase]: https://www.crunchbase.com/person/peter-boling
[💖💲crunchbase-img]: https://img.shields.io/badge/peter--boling-purple?style=flat&logo=crunchbase
[💖🐘ruby-mast]: https://ruby.social/@galtzo
[💖🐘ruby-mast-img]: https://img.shields.io/mastodon/follow/109447111526622197?domain=https://ruby.social&style=flat&logo=mastodon&label=Ruby%20@galtzo
[💖🦋bluesky]: https://bsky.app/profile/galtzo.com
[💖🦋bluesky-img]: https://img.shields.io/badge/@galtzo.com-0285FF?style=flat&logo=bluesky&logoColor=white
[💖🌳linktree]: https://linktr.ee/galtzo
[💖🌳linktree-img]: https://img.shields.io/badge/galtzo-purple?style=flat&logo=linktree
[💖💁🏼‍♂️devto]: https://dev.to/galtzo
[💖💁🏼‍♂️devto-img]: https://img.shields.io/badge/dev.to-0A0A0A?style=flat&logo=devdotto&logoColor=white
[💖💁🏼‍♂️aboutme]: https://about.me/peter.boling
[💖💁🏼‍♂️aboutme-img]: https://img.shields.io/badge/about.me-0A0A0A?style=flat&logo=aboutme&logoColor=white
[💖🧊berg]: https://codeberg.org/pboling
[💖🐙hub]: https://github.org/pboling
[💖🛖hut]: https://sr.ht/~galtzo/
[💖🧪lab]: https://gitlab.com/pboling
[👨🏼‍🏫expsup-upwork]: https://www.upwork.com/freelancers/~014942e9b056abdf86?mp_source=share
[👨🏼‍🏫expsup-upwork-img]: https://img.shields.io/badge/UpWork-13544E?style=for-the-badge&logo=Upwork&logoColor=white
[👨🏼‍🏫expsup-codementor]: https://www.codementor.io/peterboling?utm_source=github&utm_medium=button&utm_term=peterboling&utm_campaign=github
[👨🏼‍🏫expsup-codementor-img]: https://img.shields.io/badge/CodeMentor-Get_Help-1abc9c?style=for-the-badge&logo=CodeMentor&logoColor=white
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-dotenv-merge?utm_source=rubygems-dotenv-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/kettle-rb/dotenv-merge/
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/kettle-rb/dotenv-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=Github&logoColor=green
[📜src-gh]: https://github.com/kettle-rb/dotenv-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/kettle-rb/dotenv-merge/-/wikis/home
[📜gh-wiki]: https://github.com/kettle-rb/dotenv-merge/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-examples-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-examples-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://bestgems.org/gems/dotenv-merge
[👽dl-ranki]: https://img.shields.io/gem/rd/dotenv-merge.svg
[👽oss-help]: https://www.codetriage.com/kettle-rb/dotenv-merge
[👽oss-helpi]: https://www.codetriage.com/kettle-rb/dotenv-merge/badges/users.svg
[👽version]: https://bestgems.org/gems/dotenv-merge
[👽versioni]: https://img.shields.io/gem/v/dotenv-merge.svg
[🏀qlty-mnt]: https://qlty.sh/gh/kettle-rb/projects/dotenv-merge
[🏀qlty-mnti]: https://qlty.sh/gh/kettle-rb/projects/dotenv-merge/maintainability.svg
[🏀qlty-cov]: https://qlty.sh/gh/kettle-rb/projects/dotenv-merge/metrics/code?sort=coverageRating
[🏀qlty-covi]: https://qlty.sh/gh/kettle-rb/projects/dotenv-merge/coverage.svg
[🏀codecov]: https://codecov.io/gh/kettle-rb/dotenv-merge
[🏀codecovi]: https://codecov.io/gh/kettle-rb/dotenv-merge/graph/badge.svg
[🏀coveralls]: https://coveralls.io/github/kettle-rb/dotenv-merge?branch=main
[🏀coveralls-img]: https://coveralls.io/repos/github/kettle-rb/dotenv-merge/badge.svg?branch=main
[🖐codeQL]: https://github.com/kettle-rb/dotenv-merge/security/code-scanning
[🖐codeQL-img]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/codeql-analysis.yml/badge.svg
[🚎ruby-3.2-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/ruby-3.2.yml
[🚎ruby-3.3-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/ruby-3.3.yml
[🚎ruby-3.4-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/ruby-3.4.yml
[🚎truby-24.2-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/truffleruby-24.2.yml
[🚎truby-25.0-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/truffleruby-25.0.yml
[🚎2-cov-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/coverage.yml
[🚎2-cov-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/coverage.yml/badge.svg
[🚎3-hd-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/heads.yml
[🚎3-hd-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/heads.yml/badge.svg
[🚎5-st-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/style.yml
[🚎5-st-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/style.yml/badge.svg
[🚎9-t-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/truffle.yml
[🚎9-t-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/truffle.yml/badge.svg
[🚎10-j-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/jruby.yml
[🚎10-j-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/jruby.yml/badge.svg
[🚎11-c-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/current.yml
[🚎11-c-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/current.yml/badge.svg
[🚎12-crh-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/dep-heads.yml
[🚎12-crh-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/dep-heads.yml/badge.svg
[🚎13-🔒️-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/locked_deps.yml
[🚎13-🔒️-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/locked_deps.yml/badge.svg
[🚎14-🔓️-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/unlocked_deps.yml
[🚎14-🔓️-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/unlocked_deps.yml/badge.svg
[🚎15-🪪-wf]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/license-eye.yml
[🚎15-🪪-wfi]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/license-eye.yml/badge.svg
[💎ruby-3.2i]: https://img.shields.io/badge/Ruby-3.2-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.3i]: https://img.shields.io/badge/Ruby-3.3-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.4i]: https://img.shields.io/badge/Ruby-3.4-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-4.0i]: https://img.shields.io/badge/Ruby-4.0-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-CC342D?style=for-the-badge&logo=ruby&logoColor=green
[💎ruby-headi]: https://img.shields.io/badge/Ruby-HEAD-CC342D?style=for-the-badge&logo=ruby&logoColor=blue
[💎truby-24.2i]: https://img.shields.io/badge/Truffle_Ruby-24.2-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-25.0i]: https://img.shields.io/badge/Truffle_Ruby-25.0-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-c-i]: https://img.shields.io/badge/Truffle_Ruby-current-34BCB1?style=for-the-badge&logo=ruby&logoColor=green
[💎jruby-c-i]: https://img.shields.io/badge/JRuby-current-FBE742?style=for-the-badge&logo=ruby&logoColor=green
[💎jruby-headi]: https://img.shields.io/badge/JRuby-HEAD-FBE742?style=for-the-badge&logo=ruby&logoColor=blue
[🤝gh-issues]: https://github.com/kettle-rb/dotenv-merge/issues
[🤝gh-pulls]: https://github.com/kettle-rb/dotenv-merge/pulls
[🤝gl-issues]: https://gitlab.com/kettle-rb/dotenv-merge/-/issues
[🤝gl-pulls]: https://gitlab.com/kettle-rb/dotenv-merge/-/merge_requests
[🤝cb-issues]: https://codeberg.org/kettle-rb/dotenv-merge/issues
[🤝cb-pulls]: https://codeberg.org/kettle-rb/dotenv-merge/pulls
[🤝cb-donate]: https://donate.codeberg.org/
[🤝contributing]: CONTRIBUTING.md
[🏀codecov-g]: https://codecov.io/gh/kettle-rb/dotenv-merge/graphs/tree.svg
[🖐contrib-rocks]: https://contrib.rocks
[🖐contributors]: https://github.com/kettle-rb/dotenv-merge/graphs/contributors
[🖐contributors-img]: https://contrib.rocks/image?repo=kettle-rb/dotenv-merge
[🚎contributors-gl]: https://gitlab.com/kettle-rb/dotenv-merge/-/graphs/main
[🪇conduct]: CODE_OF_CONDUCT.md
[🪇conduct-img]: https://img.shields.io/badge/Contributor_Covenant-2.1-259D6C.svg
[📌pvc]: http://guides.rubygems.org/patterns/#pessimistic-version-constraint
[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-259D6C.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📌changelog]: CHANGELOG.md
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-34495e.svg?style=flat
[📌gitmoji]: https://gitmoji.dev
[📌gitmoji-img]: https://img.shields.io/badge/gitmoji_commits-%20%F0%9F%98%9C%20%F0%9F%98%8D-34495e.svg?style=flat-square
[🧮kloc]: https://www.youtube.com/watch?v=dQw4w9WgXcQ
[🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
[🔐security]: SECURITY.md
[🔐security-img]: https://img.shields.io/badge/security-policy-259D6C.svg?style=flat
[📄copyright-notice-explainer]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year
[📄license]: LICENSE.md
[📄license-ref]: AGPL-3.0-only.md
[📄license-img]: https://img.shields.io/badge/License-AGPL--3.0--only-259D6C.svg
[📄license-compat]: https://www.apache.org/legal/resolved.html#category-x
[📄license-compat-img]: https://img.shields.io/badge/Apache_Incompatible:_Category_X-✗-C0392B.svg?style=flat&logo=Apache
[📄ilo-declaration]: https://www.ilo.org/declaration/lang--en/index.htm
[📄ilo-declaration-img]: https://img.shields.io/badge/ILO_Fundamental_Principles-✓-259D6C.svg?style=flat
[🚎yard-current]: http://rubydoc.info/gems/dotenv-merge
[🚎yard-head]: https://dotenv-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/kettle-rb/dotenv-merge/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
