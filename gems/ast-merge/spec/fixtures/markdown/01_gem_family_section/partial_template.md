### The `*-merge` Gem Family

The `*-merge` gem family provides intelligent, AST-based merging for various file formats. At the foundation is [tree_haver][tree_haver], which provides a unified cross-Ruby parsing API that works seamlessly across MRI, JRuby, and TruffleRuby.

| Gem                                      | Language<br>/ Format | Parser Backend(s)                                                                                   | Description                                                                      |
|------------------------------------------|----------------------|-----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| [tree_haver][tree_haver]                 | Multi                | MRI C, Rust, FFI, Java, Prism, Psych, Commonmarker, Markly, Citrus                                  | **Foundation**: Cross-Ruby adapter for parsing libraries (like Faraday for HTTP) |
| [ast-merge][ast-merge]                   | Text                 | internal                                                                                            | **Infrastructure**: Shared base classes and merge logic for all `*-merge` gems   |
| [bash-merge][bash-merge]                 | Bash                 | [tree-sitter-bash][ts-bash] (via tree_haver)                                                        | Smart merge for Bash scripts                                                     |
| [commonmarker-merge][commonmarker-merge] | Markdown             | [Commonmarker][commonmarker] (via tree_haver)                                                       | Smart merge for Markdown (CommonMark via comrak Rust)                            |
| [dotenv-merge][dotenv-merge]             | Dotenv               | internal                                                                                            | Smart merge for `.env` files                                                     |
| [json-merge][json-merge]                 | JSON                 | [tree-sitter-json][ts-json] (via tree_haver)                                                        | Smart merge for JSON files                                                       |
| [jsonc-merge][jsonc-merge]               | JSONC                | [tree-sitter-jsonc][ts-jsonc] (via tree_haver)                                                      | ⚠️ Proof of concept; Smart merge for JSON with Comments                          |
| [markdown-merge][markdown-merge]         | Markdown             | [Commonmarker][commonmarker] / [Markly][markly] (via tree_haver)                                    | **Foundation**: Shared base for Markdown mergers with inner code block merging   |
| [markly-merge][markly-merge]             | Markdown             | [Markly][markly] (via tree_haver)                                                                   | Smart merge for Markdown (CommonMark via cmark-gfm C)                            |
| [prism-merge][prism-merge]               | Ruby                 | [Prism][prism] (`prism` std lib gem)                                                                | Smart merge for Ruby source files                                                |
| [psych-merge][psych-merge]               | YAML                 | [Psych][psych] (`psych` std lib gem)                                                                | Smart merge for YAML files                                                       |
| [rbs-merge][rbs-merge]                   | RBS                  | [tree-sitter-bash][ts-rbs] (via tree_haver), [RBS][rbs] (`rbs` std lib gem)                         | Smart merge for Ruby type signatures                                             |
| [toml-merge][toml-merge]                 | TOML                 | [Citrus + toml-rb][toml-rb] (default, via tree_haver), [tree-sitter-toml][ts-toml] (via tree_haver) | Smart merge for TOML files                                                       |

#### Backend Platform Compatibility

tree_haver supports multiple parsing backends, but not all backends work on all Ruby platforms:

| Platform 👉️<br> TreeHaver Backend 👇️         | MRI | JRuby | TruffleRuby | Notes                                               |
|------------------------------------------------|:---:|:-----:|:-----------:|-----------------------------------------------------|
| **MRI** ([ruby_tree_sitter][ruby_tree_sitter]) |  ✅  |   ❌   |      ❌      | C extension, MRI only                               |
| **Rust** ([tree_stump][tree_stump])            |  ✅  |   ❌   |      ❌      | Rust extension via magnus/rb-sys, MRI only          |
| **FFI**                                        |  ✅  |   ✅   |      ❌      | TruffleRuby's FFI doesn't support `STRUCT_BY_VALUE` |
| **Java** ([jtreesitter][jtreesitter])          |  ❌  |   ✅   |      ❌      | JRuby only, requires grammar JARs                   |
| **Prism**                                      |  ✅  |   ✅   |      ✅      | Ruby parsing, stdlib in Ruby 3.4+                   |
| **Psych**                                      |  ✅  |   ✅   |      ✅      | YAML parsing, stdlib                                |
| **Citrus**                                     |  ✅  |   ✅   |      ✅      | Pure Ruby, no native dependencies                   |
| **Commonmarker**                               |  ✅  |   ❌   |      ❓      | Rust extension for Markdown                         |
| **Markly**                                     |  ✅  |   ❌   |      ❓      | C extension for Markdown                            |

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
[prism]: https://github.com/ruby/prism
[psych]: https://github.com/ruby/psych
[ts-json]: https://github.com/tree-sitter/tree-sitter-json
[ts-jsonc]: https://gitlab.com/WhyNotHugo/tree-sitter-jsonc
[ts-bash]: https://github.com/tree-sitter/tree-sitter-bash
[ts-rbs]: https://github.com/joker1007/tree-sitter-rbs
[ts-toml]: https://github.com/tree-sitter-grammars/tree-sitter-toml
[dotenv]: https://github.com/bkeepers/dotenv
[rbs]: https://github.com/ruby/rbs
[toml-rb]: https://github.com/emancu/toml-rb
[markly]: https://github.com/ioquatix/markly
[commonmarker]: https://github.com/gjtorikian/commonmarker
[ruby_tree_sitter]: https://github.com/Faveod/ruby-tree-sitter
[tree_stump]: https://github.com/joker1007/tree_stump
[jtreesitter]: https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter

