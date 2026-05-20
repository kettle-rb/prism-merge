[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang] [![structuredmerge Logo by Aboling0, CC BY-SA 4.0][🖼️structuredmerge-i]][🖼️structuredmerge]

[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg
[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN
[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg
[🖼️ruby-lang]: https://www.ruby-lang.org/
[🖼️structuredmerge-i]: https://logos.galtzo.com/assets/images/structuredmerge/avatar-192px.svg
[🖼️structuredmerge]: https://github.com/structuredmerge

# ☯️ Rbs::Merge

[![Version][👽versioni]][👽version] [![GitHub tag (latest SemVer)][⛳️tag-img]][⛳️tag] [![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0][📄license-img]][📄license] [![Downloads Rank][👽dl-ranki]][👽dl-rank] [![CI Current][🚎11-c-wfi]][🚎11-c-wf]

`if ci_badges.map(&:color).detect { it != "green"}` ☝️ [let me know][🖼️galtzo-discord], as I may have missed the [discord notification][🖼️galtzo-discord].

---

`if ci_badges.map(&:color).all? { it == "green"}` 👇️ send money so I can do more of this. FLOSS maintenance is now my full-time job.

[![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]

<details>
 <summary>👣 How will this project approach the September 2025 hostile takeover of RubyGems? 🚑️</summary>

I've summarized my thoughts in [this blog post](https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo).

</details>

## 🌻 Synopsis

Rbs::Merge is a standalone Ruby module that intelligently merges two versions of an RBS (Ruby Signature) file using the official RBS parser. It's like a smart "git merge" specifically designed for RBS type definitions. Built on top of [ast-merge][ast-merge], it shares the same architecture as [prism-merge][prism-merge] for Ruby source files.

### Key Features

- **RBS-Aware**: Uses the official RBS parser to understand type signature structure
- **Intelligent**: Matches declarations by structural signatures (class names, method names, type aliases)
- **Recursive Merge**: Automatically merges class and module bodies recursively, intelligently combining nested method definitions and members
- **Comment-Preserving**: Comments are properly attached to relevant declarations
- **Freeze Block Support**: Respects freeze markers (default: `rbs-merge:freeze` / `rbs-merge:unfreeze`) for merge control - customizable to match your project's conventions
- **Full Provenance**: Tracks origin of every declaration
- **Standalone**: Minimal dependencies - just `rbs` and `ast-merge`
- **Customizable**:
    - `signature_generator` - callable custom signature generators
    - `preference` - setting of `:template`, `:destination`, or a Hash for per-node-type preferences
    - `node_splitter` - Hash mapping node types to callables for per-node-type merge customization (see [ast-merge][ast-merge] docs)
    - `add_template_only_nodes` - setting to retain declarations that do not exist in destination
    - `freeze_token` - customize freeze block markers (default: `"rbs-merge"`)

### Supported RBS Declarations

| Declaration Type | Signature Format | Matching Behavior |
| --- | --- | --- |
| `Class` | `[:class, name]` | Classes match by name |
| `Module` | `[:module, name]` | Modules match by name |
| `Interface` | `[:interface, name]` | Interfaces match by name |
| `TypeAlias` | `[:type_alias, name]` | Type aliases match by name |
| `Constant` | `[:constant, name]` | Constants match by name |
| `Global` | `[:global, name]` | Global variables match by name |
| `MethodDefinition` | `[:method, name, kind]` | Methods match by name and kind (instance/singleton) |
| `Alias` | `[:alias, new_name, old_name]` | Method aliases match by both names |
| `AttrReader` | `[:attr_reader, name]` | Attr readers match by name |
| `AttrWriter` | `[:attr_writer, name]` | Attr writers match by name |
| `AttrAccessor` | `[:attr_accessor, name]` | Attr accessors match by name |
| `Include` | `[:include, name]` | Include directives match by module name |
| `Extend` | `[:extend, name]` | Extend directives match by module name |
| `Prepend` | `[:prepend, name]` | Prepend directives match by module name |
| `InstanceVariable` | `[:ivar, name]` | Instance variables match by name |
| `ClassInstanceVariable` | `[:civar, name]` | Class instance variables match by name |
| `ClassVariable` | `[:cvar, name]` | Class variables match by name |

### Example

```ruby
require "rbs/merge"

template = File.read("template.rbs")
destination = File.read("destination.rbs")

merger = Rbs::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.rbs", result.to_s)
```


## 💡 Info you can shake a stick at

| Tokens to Remember | [![Gem name][⛳️name-img]][⛳️gem-name] [![Gem namespace][⛳️namespace-img]][⛳️gem-namespace] |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Works with MRI Ruby 4 | [![Ruby 4.0 Compat][💎ruby-4.0i]][🚎11-c-wf] [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf]|
| Support & Community | [![Join Me on Daily.dev's RubyFriends][✉️ruby-friends-img]][✉️ruby-friends] [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite] [![Get help from me on Upwork][👨🏼‍🏫expsup-upwork-img]][👨🏼‍🏫expsup-upwork] [![Get help from me on Codementor][👨🏼‍🏫expsup-codementor-img]][👨🏼‍🏫expsup-codementor] |
| Source | [![Source on GitLab.com][📜src-gl-img]][📜src-gl] [![Source on CodeBerg.org][📜src-cb-img]][📜src-cb] [![Source on Github.com][📜src-gh-img]][📜src-gh] [![The best SHA: dQw4w9WgXcQ!][🧮kloc-img]][🧮kloc] |
| Documentation | [![Current release on RubyDoc.info][📜docs-cr-rd-img]][🚎yard-current] [![YARD on Galtzo.com][📜docs-head-rd-img]][🚎yard-head] [![Maintainer Blog][🚂maint-blog-img]][🚂maint-blog] [![GitLab Wiki][📜gl-wiki-img]][📜gl-wiki] [![GitHub Wiki][📜gh-wiki-img]][📜gh-wiki] |
| Compliance | [![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0][📄license-img]][📄license] [![Apache license compatibility: Category X][📄license-compat-img]][📄license-compat] [![📄ilo-declaration-img]][📄ilo-declaration] [![Security Policy][🔐security-img]][🔐security] [![Contributor Covenant 2.1][🪇conduct-img]][🪇conduct] [![SemVer 2.0.0][📌semver-img]][📌semver] |
| Style | [![Enforced Code Style Linter][💎rlts-img]][💎rlts] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog] [![Gitmoji Commits][📌gitmoji-img]][📌gitmoji] [![Compatibility appraised by: appraisal2][💎appraisal2-img]][💎appraisal2] |
| Maintainer 🎖️ | [![Follow Me on LinkedIn][💖🖇linkedin-img]][💖🖇linkedin] [![Follow Me on Ruby.Social][💖🐘ruby-mast-img]][💖🐘ruby-mast] [![Follow Me on Bluesky][💖🦋bluesky-img]][💖🦋bluesky] [![Contact Maintainer][🚂maint-contact-img]][🚂maint-contact] [![My technical writing][💖💁🏼‍♂️devto-img]][💖💁🏼‍♂️devto] |
| `...` 💖 | [![Find Me on WellFound:][💖✌️wellfound-img]][💖✌️wellfound] [![Find Me on CrunchBase][💖💲crunchbase-img]][💖💲crunchbase] [![My LinkTree][💖🌳linktree-img]][💖🌳linktree] [![More About Me][💖💁🏼‍♂️aboutme-img]][💖💁🏼‍♂️aboutme] [🧊][💖🧊berg] [🐙][💖🐙hub] [🛖][💖🛖hut] [🧪][💖🧪lab] |

### Compatibility

Compatible with MRI Ruby 4.0.0+, and concordant releases of JRuby, and TruffleRuby.

| 🚚 _Amazing_ test matrix was brought to you by | 🔎 appraisal2 🔎 and the color 💚 green 💚 |
|------------------------------------------------|--------------------------------------------------------|
| 👟 Check it out! | ✨ [github.com/appraisal-rb/appraisal2][💎appraisal2] ✨ |

<details markdown="1">
<summary>StructuredMerge package family and backend compatibility</summary>

StructuredMerge packages provide fixture-backed merge behavior for document, configuration, source, archive, and binary formats. Shared contracts live in the [fixtures repository][sm-family-fixtures], while [Go][sm-family-go], [Ruby][sm-family-ruby], [Rust][sm-family-rust], and [TypeScript][sm-family-typescript] packages expose language-native APIs over the same behavior.

| Package | Layer | Families | What it provides |
|---|---|---|---|
| [ast-template][sm-family-ast-template] | workflow | template, readme | Shared template application, package README section sync, and package-directory convergence workflows. |
| [ast-merge][sm-family-ast-merge] | core | template, review, structured-edit | Provider-neutral contracts, token resolution, review state, and execution reports. |
| [tree_haver][sm-family-tree-haver] | backend substrate | parser, backend | Backend selection, language-pack integration, position data, and capability reporting. |
| [markdown-merge][sm-family-markdown-merge] | family | markdown | Markdown heading, fenced-code, nested-family, and provider-neutral Markdown behavior. |
| [json-merge][sm-family-json-merge] | family | json, jsonc | JSON and JSONC object, array, scalar, and parser-backed owner behavior. |
| [toml-merge][sm-family-toml-merge] | family | toml | TOML table, value, parser, and backend behavior. |
| [yaml-merge][sm-family-yaml-merge] | family | yaml | YAML mapping, sequence, scalar, anchor, and backend behavior. |
| [ruby-merge][sm-family-ruby-merge] | family | ruby-source | Ruby source entity matching, require ordering, constants, classes, modules, and methods. |
| [bash-merge][sm-family-bash-merge] | family | shell-source | Bash assignment, function, heredoc, comment, and shell block behavior. |
| [rbs-merge][sm-family-rbs-merge] | family | ruby-signature | RBS declarations, classes, modules, interfaces, methods, aliases, and comments. |
| [dotenv-merge][sm-family-dotenv-merge] | family | env-config | Environment key matching, comments, freeze regions, and template env files. |
| [plain-merge][sm-family-plain-merge] | family | plain-text | Plain text preservation, line ownership, diagnostics, and fallback behavior. |
| [zip-merge][sm-family-zip-merge] | family | zip, archive | ZIP member planning, archive entry ownership, and raw member preservation. |
| [binary-merge][sm-family-binary-merge] | family | binary | Binary preservation, byte-range ownership, and diagnostics behavior. |

| Backend package | Family | What it provides |
|---|---|---|
| [commonmarker-merge][sm-family-commonmarker-merge] | markdown | CommonMarker-backed Markdown parsing and merge behavior for Ruby. |
| [markly-merge][sm-family-markly-merge] | markdown | Markly-backed Markdown parsing and merge behavior for Ruby. |
| [kramdown-merge][sm-family-kramdown-merge] | markdown | Kramdown-backed Markdown parsing and merge behavior for Ruby. |
| [psych-merge][sm-family-psych-merge] | yaml | Psych-backed YAML parsing and merge behavior for Ruby. |
| [citrus-toml-merge][sm-family-citrus-toml-merge] | toml | Citrus-backed TOML parsing and merge behavior for Ruby. |
| [parslet-toml-merge][sm-family-parslet-toml-merge] | toml | Parslet-backed TOML parsing and merge behavior for Ruby. |
| [prism-merge][sm-family-prism-merge] | ruby-source | Prism-backed Ruby source parsing and merge behavior for Ruby. |

Backend packages are implementation-specific providers for a canonical family package. The family package owns the user-facing behavior contract; provider packages document parser-specific defaults, capabilities, and diagnostics.

[sm-family-fixtures]: https://github.com/structuredmerge/structuredmerge-fixtures
[sm-family-go]: https://github.com/structuredmerge/structuredmerge-go
[sm-family-ruby]: https://github.com/structuredmerge/structuredmerge-ruby
[sm-family-rust]: https://github.com/structuredmerge/structuredmerge-rust
[sm-family-typescript]: https://github.com/structuredmerge/structuredmerge-typescript
[sm-family-ast-template]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template
[sm-family-ast-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge
[sm-family-tree-haver]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver
[sm-family-markdown-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge
[sm-family-json-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge
[sm-family-toml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/toml-merge
[sm-family-yaml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/yaml-merge
[sm-family-ruby-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ruby-merge
[sm-family-bash-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/bash-merge
[sm-family-rbs-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge
[sm-family-dotenv-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/dotenv-merge
[sm-family-plain-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge
[sm-family-zip-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/zip-merge
[sm-family-binary-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/binary-merge
[sm-family-commonmarker-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge
[sm-family-markly-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge
[sm-family-kramdown-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge
[sm-family-psych-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge
[sm-family-citrus-toml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge
[sm-family-parslet-toml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge
[sm-family-prism-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge

</details>



## ✨ Installation

Install the gem and add to the application's Gemfile by executing:

```console
bundle add rbs-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install rbs-merge
```

## ⚙️ Configuration

Rbs::Merge works out of the box with zero configuration, but offers customization options for advanced use cases.

### Signature Match Preference

Control which version to use when declarations have matching signatures but different content:

```ruby
# Use template version (for updating type definitions from a canonical source)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  preference: :template,
)

# Use destination version (for preserving local type customizations)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  preference: :destination,  # This is the default
)
```

**When to use each:**

- **`:template`** - Template contains canonical/updated type definitions

    - Generated RBS files from `rbs prototype` that should replace older versions
    - Type definition updates from upstream libraries
    - Standardized type signatures that should be enforced

- **`:destination`** (default) - Destination contains customizations

    - Hand-tuned type definitions with more specific types
    - Local overrides for library types
    - Project-specific type annotations

### Template-Only Declarations

Control whether to add declarations that only exist in the template:

```ruby
# Add template-only declarations (for merging new type definitions)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: true,
)

# Skip template-only declarations (for templates with placeholder types)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: false,  # This is the default
)
```

**When to use each:**

- **`true`** - Template has new type definitions to add

    - New classes/modules from updated code
    - New method signatures that need type annotations
    - Required type aliases or constants

- **`false`** (default) - Template has placeholder/example types

    - Example type definitions that shouldn't be added
    - Generated types that may not apply to destination

### Combined Configuration

For different merge scenarios:

```ruby
# Scenario 1: Update types from generated RBS (template wins, add new types)
merger = Rbs::Merge::SmartMerger.new(
  generated_rbs,
  existing_rbs,
  preference: :template,
  add_template_only_nodes: true,
)
# Result: All type definitions updated to match generated, new types added

# Scenario 2: Preserve custom types (destination wins, skip template-only)
merger = Rbs::Merge::SmartMerger.new(
  library_types,
  custom_types,
  preference: :destination,  # default
  add_template_only_nodes: false,             # default
)
# Result: Custom type refinements preserved, template-only types skipped

# Scenario 3: Merge new types but keep customizations
merger = Rbs::Merge::SmartMerger.new(
  template_types,
  project_types,
  preference: :destination,  # Keep custom type refinements
  add_template_only_nodes: true,              # But add new type definitions
)
# Result: Existing types keep destination definitions, new types added from template
```

### Custom Signature Generator

You can provide a custom signature generator to control how declarations are matched between template and destination files:

```ruby
signature_generator = lambda do |node|
  case node
  when RBS::AST::Declarations::Class
    # Match classes by name only
    [:class, node.name.to_s]
  when RBS::AST::Declarations::TypeAlias
    # Match type aliases by name
    [:type_alias, node.name.to_s]
  when RBS::AST::Members::MethodDefinition
    # Match methods by name and kind
    [:method, node.name.to_s, node.kind]
  else
    # Return node to fall through to default signature computation
    node
  end
end

merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  signature_generator: signature_generator,
)
```

### Freeze Blocks

Protect sections in the destination file from being overwritten by the template using freeze markers.

By default, Rbs::Merge uses `rbs-merge` as the freeze token:

```ruby
# In your destination.rbs file
# rbs-merge:freeze
type custom_config = { api_key: String, timeout: Integer }
# rbs-merge:unfreeze
```

You can customize the freeze token to match your project's conventions:

```ruby
# Use a custom freeze token
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  freeze_token: "my-project",  # Now uses # my-project:freeze / # my-project:unfreeze
)
```

Freeze blocks are **always preserved** from the destination file during merge, regardless of template content. They can be placed around:

- Type alias definitions
- Class/module declarations
- Interface definitions
- Method signatures within classes
  This allows you to protect custom type definitions that should never be overwritten by template updates.

## 🔧 Basic Usage

### Simple Merge

The most basic usage merges two RBS files:

```ruby
require "rbs/merge"

template = File.read("template.rbs")
destination = File.read("destination.rbs")

merger = Rbs::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.rbs", result.to_s)
```

### Understanding the Merge

Rbs::Merge intelligently combines files by:

1.  **Parsing RBS**: Uses the official RBS parser to understand type structure
2.  **Finding Matches**: Identifies matching declarations between files by signature
3.  **Resolving Conflicts**: Uses configurable preference to choose between versions
4.  **Preserving Context**: Maintains comments and freeze blocks
    Example:

<!-- end list -->

```ruby
# template.rbs
class Foo
  def bar: (String) -> Integer
  def new_method: () -> void
end

type my_type = String

# destination.rbs
class Foo
  def bar: (Integer) -> String  # Custom signature
  def custom_method: () -> void
end

type my_type = Integer | String  # Expanded type

# After merge with default settings (destination preference):
# - Foo#bar keeps destination signature: (Integer) -> String
# - Foo#custom_method preserved (destination-only)
# - Foo#new_method NOT added (add_template_only_nodes: false)
# - my_type keeps destination definition: Integer | String
```

### Working with Generated RBS

When merging RBS files generated by `rbs prototype`:

```ruby
require "rbs/merge"

# Generate new type signatures
generated = `rbs prototype rb lib/my_class.rb`
existing = File.read("sig/my_class.rbs")

merger = Rbs::Merge::SmartMerger.new(
  generated,
  existing,
  preference: :template,  # Use generated signatures
  add_template_only_nodes: true,          # Add new methods
)
result = merger.merge

File.write("sig/my_class.rbs", result.to_s)
```

### Protecting Custom Types

Use freeze blocks to protect hand-crafted type definitions:

```ruby
# destination.rbs
class MyAPI
  # rbs-merge:freeze
  # These types are carefully tuned and should not be overwritten
  def fetch: [T] (String path, Class[T] type) -> T
  def post: [T, U] (String path, T body, Class[U] response_type) -> U
  # rbs-merge:unfreeze

  def version: () -> String
end
```

The generic method signatures in the freeze block will be preserved even if the template has simpler signatures.

### Merge Result Information

The merge result provides detailed information about decisions made:

```ruby
merger = Rbs::Merge::SmartMerger.new(template, destination)
result = merger.merge

# Get the merged content
puts result.to_s

# Check if anything was merged
puts "Empty result" if result.empty?

# Get summary of decisions
summary = result.summary
puts "Total decisions: #{summary[:total_decisions]}"
puts "Total lines: #{summary[:total_lines]}"
puts "By decision type: #{summary[:by_decision]}"
```

### Error Handling

Rbs::Merge provides specific error types for different failure modes:

```ruby
require "rbs/merge"

begin
  merger = Rbs::Merge::SmartMerger.new(template, destination)
  result = merger.merge
rescue Rbs::Merge::TemplateParseError => e
  puts "Template has syntax errors: #{e.message}"
rescue Rbs::Merge::DestinationParseError => e
  puts "Destination has syntax errors: #{e.message}"
rescue Rbs::Merge::FreezeNode::InvalidStructureError => e
  puts "Invalid freeze block structure: #{e.message}"
  puts "  Start line: #{e.start_line}"
  puts "  End line: #{e.end_line}"
end
```

## 🔐 Security

See [SECURITY.md][🔐security].

## 🤝 Contributing

If you need some ideas of where to help, you could work on adding more code coverage,
or if it is already 💯 (see [below](#code-coverage)) check [issues][🤝gh-issues] or [PRs][🤝gh-pulls],
or use the gem and think about how it could be better.

We [![Keep A Changelog][📗keep-changelog-img]][📗keep-changelog] so if you make changes, remember to update it.

See [CONTRIBUTING.md][🤝contributing] for more detailed instructions.





## 📌 Versioning

This library follows [![Semantic Versioning 2.0.0][📌semver-img]][📌semver] for its public API where practical.
For most applications, prefer the [Pessimistic Version Constraint][📌pvc] with two digits of precision.

For example:

```ruby
spec.add_dependency("rbs-merge", "~> 0.0")
```

<details markdown="1">
<summary>📌 Is "Platform Support" part of the public API? More details inside.</summary>

Dropping support for a platform can be a breaking change for affected users.
If a release changes supported platforms, it should be called out clearly in the changelog and versioned with that impact in mind.

To get a better understanding of how SemVer is intended to work over a project's lifetime,
read this article from the creator of SemVer:

- ["Major Version Numbers are Not Sacred"][📌major-versions-not-sacred]

</details>

See [CHANGELOG.md][📌changelog] for a list of releases.

## 📄 License

The gem is available under the following licenses: [AGPL-3.0-only](AGPL-3.0-only.md), [PolyForm-Small-Business-1.0.0](PolyForm-Small-Business-1.0.0.md).
See [LICENSE.md][📄license] for details.

If none of the available licenses suit your use case, please [contact us](mailto:floss@galtzo.com) to discuss a custom commercial license.

[gh-discussions]: https://github.com/structuredmerge/structuredmerge-ruby/discussions
[⛳liberapay-img]: https://img.shields.io/liberapay/goal/pboling.svg?logo=liberapay&color=a51611&style=flat
[⛳liberapay-bottom-img]: https://img.shields.io/liberapay/goal/pboling.svg?style=for-the-badge&logo=liberapay&color=a51611
[⛳liberapay]: https://liberapay.com/pboling/donate
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
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Rbs::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://bestgems.org/gems/rbs-merge
[⛳️name-img]: https://img.shields.io/badge/name-rbs--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/rbs-merge
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-rbs-merge?utm_source=rubygems-rbs-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/rbs-merge
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/rbs-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=Github&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://bestgems.org/gems/rbs-merge
[👽dl-ranki]: https://img.shields.io/gem/rd/rbs-merge.svg
[👽version]: https://bestgems.org/gems/rbs-merge
[👽versioni]: https://img.shields.io/gem/v/rbs-merge.svg
[🚎11-c-wf]: https://github.com/structuredmerge/structuredmerge-ruby/actions/workflows/current.yml
[🚎11-c-wfi]: https://github.com/structuredmerge/structuredmerge-ruby/actions/workflows/current.yml/badge.svg
[💎ruby-4.0i]: https://img.shields.io/badge/Ruby-4.0-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-CC342D?style=for-the-badge&logo=ruby&logoColor=green
[🤝gh-issues]: https://github.com/structuredmerge/structuredmerge-ruby/issues
[🤝gh-pulls]: https://github.com/structuredmerge/structuredmerge-ruby/pulls
[🤝gl-issues]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/issues
[🤝gl-pulls]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/merge_requests
[🤝cb-issues]: https://codeberg.org/structuredmerge/structuredmerge-ruby/issues
[🤝cb-pulls]: https://codeberg.org/structuredmerge/structuredmerge-ruby/pulls
[🤝cb-donate]: https://donate.codeberg.org/
[🤝contributing]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CONTRIBUTING.md
[🖐contrib-rocks]: https://contrib.rocks
[🖐contributors]: https://github.com/structuredmerge/structuredmerge-ruby/graphs/contributors
[🖐contributors-img]: https://contrib.rocks/image?repo=structuredmerge/structuredmerge-ruby
[🚎contributors-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/graphs/main
[🪇conduct]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CODE_OF_CONDUCT.md
[🪇conduct-img]: https://img.shields.io/badge/Contributor_Covenant-2.1-259D6C.svg
[📌pvc]: http://guides.rubygems.org/patterns/#pessimistic-version-constraint
[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-259D6C.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📌changelog]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CHANGELOG.md
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-34495e.svg?style=flat
[📌gitmoji]: https://gitmoji.dev
[📌gitmoji-img]: https://img.shields.io/badge/gitmoji_commits-%20%F0%9F%98%9C%20%F0%9F%98%8D-34495e.svg?style=flat-square
[🧮kloc]: https://www.youtube.com/watch?v=dQw4w9WgXcQ
[🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
[🔐security]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/SECURITY.md
[🔐security-img]: https://img.shields.io/badge/security-policy-259D6C.svg?style=flat
[📄copyright-notice-explainer]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year
[📄license]: LICENSE.md
[📄license-ref]: LICENSE.md
[📄license-img]: https://img.shields.io/badge/License-AGPL--3.0--only_OR_PolyForm--Small--Business--1.0.0-259D6C.svg
[📄license-compat]: https://www.apache.org/legal/resolved.html#category-x
[📄license-compat-img]: https://img.shields.io/badge/Apache_Incompatible:_Category_X-✗-C0392B.svg?style=flat&logo=Apache
[📄ilo-declaration]: https://www.ilo.org/declaration/lang--en/index.htm
[📄ilo-declaration-img]: https://img.shields.io/badge/ILO_Fundamental_Principles-✓-259D6C.svg?style=flat
[🚎yard-current]: http://rubydoc.info/gems/rbs-merge
[🚎yard-head]: https://rbs-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/

[ast-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge
[prism-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge
