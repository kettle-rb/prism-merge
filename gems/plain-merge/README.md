[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang] [![structuredmerge Logo by Aboling0, CC BY-SA 4.0][🖼️structuredmerge-i]][🖼️structuredmerge]

[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg
[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN
[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg
[🖼️ruby-lang]: https://www.ruby-lang.org/
[🖼️structuredmerge-i]: https://logos.galtzo.com/assets/images/structuredmerge/avatar-192px.svg
[🖼️structuredmerge]: https://github.com/structuredmerge

# ☯️ Plain::Merge

[![Version][👽versioni]][👽version] [![GitHub tag (latest SemVer)][⛳️tag-img]][⛳️tag] [![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0][📄license-img]][📄license] [![Downloads Rank][👽dl-ranki]][👽dl-rank] [![CI Heads][🚎3-hd-wfi]][🚎3-hd-wf] [![CI Runtime Dependencies @ HEAD][🚎12-crh-wfi]][🚎12-crh-wf] [![CI Current][🚎11-c-wfi]][🚎11-c-wf] [![CI Truffle Ruby][🚎9-t-wfi]][🚎9-t-wf] [![CI JRuby][🚎10-j-wfi]][🚎10-j-wf] [![Deps Locked][🚎13-🔒️-wfi]][🚎13-🔒️-wf] [![Deps Unlocked][🚎14-🔓️-wfi]][🚎14-🔓️-wf] [![CI Test Coverage][🚎2-cov-wfi]][🚎2-cov-wf] [![CI Style][🚎5-st-wfi]][🚎5-st-wf]

`if ci_badges.map(&:color).detect { it != "green"}` ☝️ [let me know][🖼️galtzo-discord], as I may have missed the [discord notification][🖼️galtzo-discord].

---

`if ci_badges.map(&:color).all? { it == "green"}` 👇️ send money so I can do more of this. FLOSS maintenance is now my full-time job.

[![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]

<details>
 <summary>👣 How will this project approach the September 2025 hostile takeover of RubyGems? 🚑️</summary>

I've summarized my thoughts in [this blog post](https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo).

</details>

## 🌻 Synopsis

`Plain::Merge` provides text-family fallback behavior for content without a richer parser. It normalizes paragraphs into blocks, compares block similarity, and reports whether two text bodies are close enough for a safe fallback decision.

### Key Features

- Paragraph/block normalization for plain text.
- Jaccard similarity scoring.
- Configurable text-refinement threshold and weights.
- Module-level `merge_text` API for fallback integrations.

## 💡 Info you can shake a stick at

| Tokens to Remember | [![Gem name][⛳️name-img]][⛳️gem-name] [![Gem namespace][⛳️namespace-img]][⛳️gem-namespace] |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Works with JRuby | [![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf] [![JRuby HEAD Compat][💎jruby-headi]][🚎3-hd-wf]|
| Works with Truffle Ruby | [![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf]|
| Works with MRI Ruby 4 | [![Ruby 4.0 Compat][💎ruby-4.0i]][🚎11-c-wf] [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf] [![Ruby HEAD Compat][💎ruby-headi]][🚎3-hd-wf]|
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
bundle add plain-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install plain-merge
```

## ⚙️ Configuration

The default similarity threshold is `Plain::Merge::DEFAULT_TEXT_REFINEMENT_THRESHOLD`. Use `Plain::Merge.is_similar(left, right, threshold)` when a caller needs to decide whether a text fallback is acceptable.

`Plain::Merge.text_feature_profile` returns the family profile used by conformance runners.

## 🔧 Basic Usage

```ruby
require "plain/merge"

result = Plain::Merge.merge_text(
  File.read("template.txt"),
  File.read("notes.txt"),
)

abort result.fetch(:diagnostics).inspect unless result.fetch(:ok)
File.write("notes.txt", result.fetch(:output))
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
spec.add_dependency("plain-merge", "~> 0.0")
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

[gh-discussions]: https://github.com/structuredmerge/plain-merge/discussions
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
[⛳️gem-namespace]: https://github.com/structuredmerge/plain-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Plain::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://bestgems.org/gems/plain-merge
[⛳️name-img]: https://img.shields.io/badge/name-plain--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/plain-merge.svg
[⛳️tag]: http://github.com/structuredmerge/plain-merge/releases
[🚂maint-blog]: http://www.railsbling.com/tags/plain-merge
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-plain-merge?utm_source=rubygems-plain-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/plain-merge/
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/plain-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=Github&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/plain-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/plain-merge/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/plain-merge/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://bestgems.org/gems/plain-merge
[👽dl-ranki]: https://img.shields.io/gem/rd/plain-merge.svg
[👽version]: https://bestgems.org/gems/plain-merge
[👽versioni]: https://img.shields.io/gem/v/plain-merge.svg
[🏀qlty-mnt]: https://qlty.sh/gh/structuredmerge/projects/plain-merge
[🏀qlty-mnti]: https://qlty.sh/gh/structuredmerge/projects/plain-merge/maintainability.svg
[🏀qlty-cov]: https://qlty.sh/gh/structuredmerge/projects/plain-merge/metrics/code?sort=coverageRating
[🏀qlty-covi]: https://qlty.sh/gh/structuredmerge/projects/plain-merge/coverage.svg
[🏀codecov]: https://codecov.io/gh/structuredmerge/plain-merge
[🏀codecovi]: https://codecov.io/gh/structuredmerge/plain-merge/graph/badge.svg
[🏀coveralls]: https://coveralls.io/github/structuredmerge/plain-merge?branch=main
[🏀coveralls-img]: https://coveralls.io/repos/github/structuredmerge/plain-merge/badge.svg?branch=main
[🖐codeQL]: https://github.com/structuredmerge/plain-merge/security/code-scanning
[🖐codeQL-img]: https://github.com/structuredmerge/plain-merge/actions/workflows/codeql-analysis.yml/badge.svg
[🚎2-cov-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/coverage.yml
[🚎2-cov-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/coverage.yml/badge.svg
[🚎3-hd-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/heads.yml
[🚎3-hd-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/heads.yml/badge.svg
[🚎5-st-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/style.yml
[🚎5-st-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/style.yml/badge.svg
[🚎9-t-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/truffle.yml
[🚎9-t-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/truffle.yml/badge.svg
[🚎10-j-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/jruby.yml
[🚎10-j-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/jruby.yml/badge.svg
[🚎11-c-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/current.yml
[🚎11-c-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/current.yml/badge.svg
[🚎12-crh-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/dep-heads.yml
[🚎12-crh-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/dep-heads.yml/badge.svg
[🚎13-🔒️-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/locked_deps.yml
[🚎13-🔒️-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/locked_deps.yml/badge.svg
[🚎14-🔓️-wf]: https://github.com/structuredmerge/plain-merge/actions/workflows/unlocked_deps.yml
[🚎14-🔓️-wfi]: https://github.com/structuredmerge/plain-merge/actions/workflows/unlocked_deps.yml/badge.svg
[💎ruby-4.0i]: https://img.shields.io/badge/Ruby-4.0-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-CC342D?style=for-the-badge&logo=ruby&logoColor=green
[💎ruby-headi]: https://img.shields.io/badge/Ruby-HEAD-CC342D?style=for-the-badge&logo=ruby&logoColor=blue
[💎truby-c-i]: https://img.shields.io/badge/Truffle_Ruby-current-34BCB1?style=for-the-badge&logo=ruby&logoColor=green
[💎jruby-c-i]: https://img.shields.io/badge/JRuby-current-FBE742?style=for-the-badge&logo=ruby&logoColor=green
[💎jruby-headi]: https://img.shields.io/badge/JRuby-HEAD-FBE742?style=for-the-badge&logo=ruby&logoColor=blue
[🤝gh-issues]: https://github.com/structuredmerge/plain-merge/issues
[🤝gh-pulls]: https://github.com/structuredmerge/plain-merge/pulls
[🤝gl-issues]: https://gitlab.com/structuredmerge/plain-merge/-/issues
[🤝gl-pulls]: https://gitlab.com/structuredmerge/plain-merge/-/merge_requests
[🤝cb-issues]: https://codeberg.org/structuredmerge/plain-merge/issues
[🤝cb-pulls]: https://codeberg.org/structuredmerge/plain-merge/pulls
[🤝cb-donate]: https://donate.codeberg.org/
[🤝contributing]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CONTRIBUTING.md
[🏀codecov-g]: https://codecov.io/gh/structuredmerge/plain-merge/graphs/tree.svg
[🖐contrib-rocks]: https://contrib.rocks
[🖐contributors]: https://github.com/structuredmerge/plain-merge/graphs/contributors
[🖐contributors-img]: https://contrib.rocks/image?repo=structuredmerge/plain-merge
[🚎contributors-gl]: https://gitlab.com/structuredmerge/plain-merge/-/graphs/main
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
[🚎yard-current]: http://rubydoc.info/gems/plain-merge
[🚎yard-head]: https://plain-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/plain-merge/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
