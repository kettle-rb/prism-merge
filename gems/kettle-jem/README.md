[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang] [![kettle-rb Logo by Aboling0, CC BY-SA 4.0][🖼️kettle-rb-i]][🖼️kettle-rb]

[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg
[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN
[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg
[🖼️ruby-lang]: https://www.ruby-lang.org/
[🖼️kettle-rb-i]: https://logos.galtzo.com/assets/images/kettle-rb/avatar-192px.svg
[🖼️kettle-rb]: https://github.com/kettle-rb

# 🔮 Kettle::Jem

[![Version][👽versioni]][👽version] [![GitHub tag (latest SemVer)][⛳️tag-img]][⛳️tag] [![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0][📄license-img]][📄license] [![Downloads Rank][👽dl-ranki]][👽dl-rank] [![CI Current][🚎11-c-wfi]][🚎11-c-wf]

`if ci_badges.map(&:color).detect { it != "green"}` ☝️ [let me know][🖼️galtzo-discord], as I may have missed the [discord notification][🖼️galtzo-discord].

---

`if ci_badges.map(&:color).all? { it == "green"}` 👇️ send money so I can do more of this. FLOSS maintenance is now my full-time job.

[![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors] [![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]

<details>
 <summary>👣 How will this project approach the September 2025 hostile takeover of RubyGems? 🚑️</summary>

I've summarized my thoughts in [this blog post](https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo).

</details>

## 🌻 Synopsis

Kettle::Jem is an AST-aware gem templating system that keeps hundreds of Ruby gems
in sync with a shared template while preserving each project's customizations.
Unlike line-based copy/merge tools, Kettle::Jem understands the *structure* of
every file it touches — Ruby via Prism, YAML via Psych, Markdown via Markly,
TOML via tree-sitter, and more — so template updates land precisely where they
belong, and project-specific additions are never clobbered.

Plugin authors can now use the dedicated [plugin authoring guide](KETTLE_JEM_PLUGINS.md)
to build `kettle-jem` extension gems against the supported plugin seam.

### Key Features

- **AST-aware merging** — 10 format-specific merge engines (prism, psych, markly, toml, json, jsonc, bash, dotenv, rbs, text)
- **Token substitution** — `{KJ|TOKEN}` patterns resolved from config, ENV, or auto-derived from gemspec
- **Freeze blocks** — protect any section from template overwrites with `# kettle-jem:freeze` / `# kettle-jem:unfreeze`
- **Per-file strategies** — `merge`, `accept_template`, `keep_destination`, or `raw_copy`
- **Multi-phase pipeline** — 11 ordered phases (service_actor-based) from config sync through duplicate checking
- **SHA-pinned GitHub Actions** — template `uses:` always wins, propagating immutable SHAs
- **Convergence in one pass** — a single `rake kettle:jem:install` applies all changes; a second run produces zero diff
- **Selftest divergence check** — CI verifies that project drift stays within a configurable threshold

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
bundle add kettle-jem
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install kettle-jem
```

## ⚙️ Configuration

Each gem that uses Kettle::Jem has a `.kettle-jem.yml` file at its root. This file controls
every aspect of how the template is applied.

### Minimal Configuration

```yaml
project_emoji: "🔮"
engines:
  - ruby
licenses:
  - MIT
tokens:
  forge:
    gh_user: "your-username"
  author:
    name: "Your Name"
    email: "you@example.com"
```

### Full Configuration Reference

```yaml
# REQUIRED — unique emoji used in badges and gemspec summary
project_emoji: "🔮"               # ENV override: KJ_PROJECT_EMOJI

# Ruby engines to include in CI matrix (remove to skip)
engines:
  - ruby
  - jruby
  - truffleruby

# SPDX license identifiers
licenses:
  - MIT

# Logo layout in README header: org | project | org_and_project
readme:
  top_logo_mode: org

# Bot accounts to exclude from contributor lists
machine_users:
  - dependabot

# Maximum allowed divergence (%) for selftest CI check
min_divergence_threshold: 5       # ENV override: KJ_MIN_DIVERGENCE_THRESHOLD

# Default merge behavior applied to all files
defaults:
  preference: "template"           # template | destination
  add_template_only_nodes: true    # add nodes that only exist in template
  freeze_token: "kettle-jem"       # marker for frozen sections

# Token values for {KJ|TOKEN} substitution
tokens:
  forge:
    gh_user: "github-username"    # ENV override: KJ_GH_USER
    gl_user: "gitlab-username"    # ENV override: KJ_GL_USER
    cb_user: "codeberg-username"  # ENV override: KJ_CB_USER
    sh_user: "sourcehut-user"     # ENV override: KJ_SH_USER
  author:
    name: "Full Name"             # ENV override: KJ_AUTHOR_NAME
    given_names: "Full"           # ENV override: KJ_AUTHOR_GIVEN_NAMES
    family_names: "Name"          # ENV override: KJ_AUTHOR_FAMILY_NAMES
    email: "you@example.com"      # ENV override: KJ_AUTHOR_EMAIL
    domain: "example.com"         # ENV override: KJ_AUTHOR_DOMAIN
    orcid: "0000-0000-0000-0000"  # ENV override: KJ_AUTHOR_ORCID
  funding:
    patreon: "username"           # ENV override: KJ_FUNDING_PATREON
    kofi: "username"              # ENV override: KJ_FUNDING_KOFI
    paypal: "username"            # ENV override: KJ_FUNDING_PAYPAL
    buymeacoffee: "username"      # ENV override: KJ_FUNDING_BUYMEACOFFEE
    polar: "username"             # ENV override: KJ_FUNDING_POLAR
    liberapay: "username"         # ENV override: KJ_FUNDING_LIBERAPAY
    issuehunt: "username"         # ENV override: KJ_FUNDING_ISSUEHUNT
  social:
    mastodon: "username"          # ENV override: KJ_SOCIAL_MASTODON
    bluesky: "user.bsky.social"   # ENV override: KJ_SOCIAL_BLUESKY
    linktree: "username"          # ENV override: KJ_SOCIAL_LINKTREE
    devto: "username"             # ENV override: KJ_SOCIAL_DEVTO

# Glob-based overrides (first match wins)
patterns:
  - path: "certs/**"
    strategy: raw_copy

# Per-file overrides
files:
  Rakefile:
    strategy: merge
    preference: destination        # preserve local tasks
  AGENTS.md:
    strategy: accept_template      # always use template version
```

### Framework Matrix vs. Appraisals

`workflows.preset: framework` and `workflows.framework_matrix` are meant for a
simple 2D matrix: **Ruby versions × one framework gem/version axis**. This is a
good fit when you want kettle-jem to generate CI matrix entries and gemfile
references directly without using `Appraisals`.

If you need a deeper or more complex matrix, prefer
**`kettle-jem-appraisals`**, which generates `Appraisals` entries and is the
better fit for Appraisals-style combinations.

### Strategies

| Strategy           | Behavior                                                              |
|--------------------|-----------------------------------------------------------------------|
| `merge`            | Resolve tokens, then AST-merge template + destination (default)       |
| `accept_template`  | Resolve tokens, overwrite destination with template result            |
| `keep_destination`  | Skip entirely — no merge, no creation                                |
| `raw_copy`         | Copy bytes as-is — no token resolution, no merge (for binary assets) |

### Token Substitution

Tokens use `{KJ|TOKEN}` syntax and are resolved in priority order:

1. **ENV variables** (highest) — e.g., `KJ_AUTHOR_NAME`
2. **`.kettle-jem.yml` `tokens:` section** — explicit values
3. **Auto-derived from gemspec** (lowest) — author name, email, domain

Common tokens:

| Token                  | Source                            |
|------------------------|-----------------------------------|
| `{KJ\|GEM_NAME}`       | Gem name from gemspec             |
| `{KJ\|NAMESPACE}`      | Ruby module namespace             |
| `{KJ\|AUTHOR:NAME}`    | Author full name                  |
| `{KJ\|AUTHOR:EMAIL}`   | Author email                      |
| `{KJ\|GH:USER}`        | GitHub username                   |
| `{KJ\|PROJECT_EMOJI}`  | Project emoji from config         |
| `{KJ\|MIN_RUBY}`       | Minimum Ruby version              |
| `{KJ\|FREEZE_TOKEN}`   | Freeze marker name                |

### Freeze Blocks

Protect sections in any file from template overwrites:

```ruby
# kettle-jem:freeze
gem "my-local-fork", path: "../custom"
# kettle-jem:unfreeze
```

Content between freeze/unfreeze markers is always preserved from the destination,
regardless of what the template contains. Works in all supported formats (Ruby, YAML,
Markdown, TOML, JSON, Bash, etc.).

### Merge Engine Selection

Kettle::Jem selects the merge engine by file type:

| File Pattern                                             | Merge Engine  | Key Behaviors                              |
|----------------------------------------------------------|---------------|--------------------------------------------|
| `*.rb`, `Gemfile`, `*.gemspec`, `Rakefile`, `Appraisals` | Prism::Merge  | Three-phase matching, gemspec var renaming |
| `*.yml`, `*.yaml`                                        | Psych::Merge  | SHA-pinned `uses:`, per-key preferences    |
| `*.md`, `*.markdown`                                     | Markly::Merge | Heading/list matching, inner list merge    |
| `*.toml`                                                 | Toml::Merge   | Sort keys, table matching                  |
| `*.json`                                                 | Json::Merge   | Key-based matching                         |
| `*.jsonc`                                                | Json::Merge   | With comment preservation                  |
| `*.sh`, `*.bash`, `.envrc`                               | Bash::Merge   | Block matching                             |
| `.env*`                                                  | Dotenv::Merge | KEY=value matching                         |
| `*.rbs`                                                  | RBS::Merge    | Type signature matching                    |
| `.gitignore`                                             | Text::Merge   | Intentional line-based merge               |

> **No silent fallback:** If a tree-sitter grammar is unavailable for a file
> type that requires AST merging, kettle-jem will **fail** (default) or
> **skip** the file — never silently degrade to text-based merging.
> See `PARSE_ERROR_MODE` below.

## 🔧 Basic Usage

### Initial Setup

```bash
gem install kettle-jem
cd my-gem
kettle-jem
```

The setup CLI runs a two-phase bootstrap:

1. **Bootstrap** — creates `.kettle-jem.yml`, installs modular gemfiles, ensures dev dependencies
2. **Bundled** — loads the full runtime and runs `rake kettle:jem:install`

### Applying Template Updates

After initial setup, re-run the template process to pull in updates:

```bash
bundle exec rake kettle:jem:install
```

This applies all 11 phases:

| Phase | Description                          | Files Affected                        |
|-------|--------------------------------------|---------------------------------------|
| 0     | Config sync                          | `.kettle-jem.yml`                     |
| 1     | Dev container                        | `.devcontainer/`                      |
| 2     | GitHub workflows                     | `.github/workflows/`, `FUNDING.yml`   |
| 3     | Quality config                       | `.qlty/qlty.toml`                     |
| 4     | Modular gemfiles                     | `gemfiles/modular/`                   |
| 5     | Spec helper                          | `spec/spec_helper.rb`                 |
| 6     | Environment templates                | `.env.local.example`                  |
| 7     | Remaining files                      | gemspec, README, LICENSE, Rakefile, … |
| 8     | Git hooks                            | `.git-hooks/`                         |
| 9     | License files                        | `LICENSE*`                            |
| 10    | Duplicate check                      | _(validation only)_                   |

Each phase is implemented as a composable [service_actor](https://github.com/sunny/actor)
actor, enabling per-phase statistics (📄 templates, 🆕 created, 📋 pre-existing,
🟰 identical, ✏️ changed) and future slice-based workflows.

### Checking Divergence

CI can verify that a project hasn't drifted too far from the template:

```bash
bundle exec rake kettle:jem:selftest
```

This re-applies the template in a temporary checkout and measures the diff.
Output is condensed to two summary lines after the template run:

```
[selftest] 📄  Report - tmp/template_test/report/summary.md
[selftest] ✅  Score: 100.0% · Divergence: 0.0% · Threshold: fail when divergence reaches 5.0%
```

If divergence exceeds `min_divergence_threshold` (default 5%), the check fails.

### Workflow-Specific Options

For GitHub Actions workflows, the template always wins for `uses:` lines
(SHA-pinned action references) while destination wins for job configuration:

```yaml
# Template updates this SHA automatically:
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683

# Your matrix customizations are preserved:
matrix:
  ruby: ["3.2", "3.3", "3.4"]
```

### Per-File Overrides

Override merge behavior for specific files in `.kettle-jem.yml`:

```yaml
files:
  Rakefile:
    strategy: merge
    preference: destination     # keep your custom tasks
  certs/my.pem:
    strategy: raw_copy          # binary file, no merging
  generated/report.md:
    strategy: keep_destination  # never touch this file
```

### Environment Variables & CLI Options

Kettle::Jem behavior is controlled via environment variables (which double as
Rake task arguments) and CLI flags passed to `kettle-jem setup`.

#### Merge & Error Handling

| Variable | CLI Flag | Default | Description |
|----------|----------|---------|-------------|
| `FAILURE_MODE` | `--failure-mode=VAL` | `error` | How general merge failures are handled. `error` raises and halts; `rescue` logs a warning and uses unmerged content. |
| `PARSE_ERROR_MODE` | — | `fail` | How AST parser unavailability is handled. `fail` raises immediately (recommended); `skip` warns and preserves the destination file unchanged. **There is no text-merge fallback** — AST merge or nothing. |

#### Task Control

| Variable | CLI Flag | Default | Description |
|----------|----------|---------|-------------|
| `allowed` | `--allowed=VAL` | `true` | Set to `false`/`0`/`no` to require manual review of env file changes before continuing. |
| — | `--interactive` | _(off)_ | Enable interactive prompts (opt-in). Overrides the default non-interactive behavior. |
| `KETTLE_JEM_VERBOSE` | `--verbose` | `false` | Show detailed output including per-file messages and setup progress. Overrides the default quiet behavior. |
| `only` | `--only=VAL` | _(all)_ | Comma-separated glob patterns — only template files matching at least one pattern are processed. |
| `include` | `--include=VAL` | _(all)_ | Comma-separated glob patterns — additional files to include beyond the default set. |
| `hook_templates` | `--hook_templates=VAL` | _(prompt)_ | Git hook install location: `l`/`local`, `g`/`global`, or `n`/`none`. Also via `KETTLE_DEV_HOOK_TEMPLATES`. |

#### Config & Identity (KJ_ prefix)

These map directly to `.kettle-jem.yml` keys, seed freshly created configs,
fill missing keys during config sync, and act as runtime overrides.

| Variable | Description |
|----------|-------------|
| `KJ_PROJECT_EMOJI` | Project identifying emoji (e.g. `🪙`). Required in config. |
| `KJ_MIN_DIVERGENCE_THRESHOLD` | Selftest divergence threshold for `min_divergence_threshold`. |
| `KJ_AUTHOR_NAME` | Gem author full name |
| `KJ_AUTHOR_EMAIL` | Gem author email |
| `KJ_AUTHOR_DOMAIN` | Author website domain (derived from email if unset) |
| `KJ_AUTHOR_GIVEN_NAMES` | First/given names |
| `KJ_AUTHOR_FAMILY_NAMES` | Last/family names |
| `KJ_AUTHOR_ORCID` | ORCID identifier |
| `KJ_GH_USER` | GitHub username |
| `KJ_GL_USER` | GitLab username |
| `KJ_CB_USER` | Codeberg username |
| `KJ_SH_USER` | SourceHut username |

#### Workspace & Funding

| Variable | Description |
|----------|-------------|
| `KETTLE_RB_DEV` | Workspace root for local sibling gems. `true` = `~/src/kettle-rb`; a path = that path; unset/`false` = released gems. |
| `KETTLE_DEV_DEBUG` | Set to `true` for verbose debug output. |
| `FUNDING_ORG` | OpenCollective organization handle for FUNDING.yml. Auto-derived from git remote if unset. |
| `OPENCOLLECTIVE_HANDLE` | Alternative to `FUNDING_ORG` for personal OpenCollective pages. |
| `KJ_FUNDING_PATREON` | Patreon handle for FUNDING.yml |
| `KJ_FUNDING_KOFI` | Ko-fi handle for FUNDING.yml |
| `KJ_FUNDING_PAYPAL` | PayPal handle for FUNDING.yml |
| `KJ_FUNDING_BUYMEACOFFEE` | Buy Me a Coffee handle for funding links |
| `KJ_FUNDING_POLAR` | Polar handle for funding links |
| `KJ_FUNDING_LIBERAPAY` | Liberapay handle for funding links |
| `KJ_FUNDING_ISSUEHUNT` | IssueHunt handle for funding links |
| `KJ_SOCIAL_MASTODON` | Mastodon handle for social/profile links |
| `KJ_SOCIAL_BLUESKY` | Bluesky handle for social/profile links |
| `KJ_SOCIAL_LINKTREE` | Linktree handle for social/profile links |
| `KJ_SOCIAL_DEVTO` | DEV Community handle for social/profile links |

#### Rake Task Examples

```bash
# Standard template update (quiet, non-interactive — the default)
bundle exec rake kettle:jem:install

# Verbose output
KETTLE_JEM_VERBOSE=true bundle exec rake kettle:jem:install

# Interactive mode (prompts before each change)
bundle exec rake kettle:jem:install force=false

# Only workflow files, skip unparseable
PARSE_ERROR_MODE=skip bundle exec rake kettle:jem:install only=".github/**"

# Rescue on merge failure (don't halt)
bundle exec rake kettle:jem:install FAILURE_MODE=rescue
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
spec.add_dependency("kettle-jem", "~> 0.0")
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
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Kettle::Jem-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://bestgems.org/gems/kettle-jem
[⛳️name-img]: https://img.shields.io/badge/name-kettle--jem-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/kettle-jem
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-kettle-jem?utm_source=rubygems-kettle-jem&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/kettle-jem
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/kettle-jem
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=Github&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://bestgems.org/gems/kettle-jem
[👽dl-ranki]: https://img.shields.io/gem/rd/kettle-jem.svg
[👽version]: https://bestgems.org/gems/kettle-jem
[👽versioni]: https://img.shields.io/gem/v/kettle-jem.svg
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
[🤝contributing]: https://github.com/kettle-rb/kettle-jem/blob/main/CONTRIBUTING.md
[🖐contrib-rocks]: https://contrib.rocks
[🖐contributors]: https://github.com/structuredmerge/structuredmerge-ruby/graphs/contributors
[🖐contributors-img]: https://contrib.rocks/image?repo=structuredmerge/structuredmerge-ruby
[🚎contributors-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/graphs/main
[🪇conduct]: https://github.com/kettle-rb/kettle-jem/blob/main/CODE_OF_CONDUCT.md
[🪇conduct-img]: https://img.shields.io/badge/Contributor_Covenant-2.1-259D6C.svg
[📌pvc]: http://guides.rubygems.org/patterns/#pessimistic-version-constraint
[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-259D6C.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📌changelog]: https://github.com/kettle-rb/kettle-jem/blob/main/CHANGELOG.md
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-34495e.svg?style=flat
[📌gitmoji]: https://gitmoji.dev
[📌gitmoji-img]: https://img.shields.io/badge/gitmoji_commits-%20%F0%9F%98%9C%20%F0%9F%98%8D-34495e.svg?style=flat-square
[🧮kloc]: https://www.youtube.com/watch?v=dQw4w9WgXcQ
[🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
[🔐security]: https://github.com/kettle-rb/kettle-jem/blob/main/SECURITY.md
[🔐security-img]: https://img.shields.io/badge/security-policy-259D6C.svg?style=flat
[📄copyright-notice-explainer]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year
[📄license]: LICENSE.md
[📄license-ref]: LICENSE.md
[📄license-img]: https://img.shields.io/badge/License-AGPL--3.0--only_OR_PolyForm--Small--Business--1.0.0-259D6C.svg
[📄license-compat]: https://www.apache.org/legal/resolved.html#category-x
[📄license-compat-img]: https://img.shields.io/badge/Apache_Incompatible:_Category_X-✗-C0392B.svg?style=flat&logo=Apache
[📄ilo-declaration]: https://www.ilo.org/declaration/lang--en/index.htm
[📄ilo-declaration-img]: https://img.shields.io/badge/ILO_Fundamental_Principles-✓-259D6C.svg?style=flat
[🚎yard-current]: http://rubydoc.info/gems/kettle-jem
[🚎yard-head]: https://kettle-jem.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
