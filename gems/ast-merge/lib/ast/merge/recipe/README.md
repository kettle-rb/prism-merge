# Ast::Merge::Recipe

`Ast::Merge::Recipe` provides declarative merge configuration that can live in YAML instead of Ruby call sites.

## The four pieces

### `Preset`

`Ast::Merge::Recipe::Preset` stores reusable merge options such as:

- `preference`
- `add_missing`
- `signature_generator`
- `node_typing`
- `match_refiner`
- `freeze_token`
- `normalize_whitespace` (forwarded only to mergers that explicitly support whitespace post-processing)
- `rehydrate_link_references`

Use `Preset#to_h` when you want to pass those options directly to a format-specific `SmartMerger`.

```ruby
preset = Ast::Merge::Recipe::Preset.load("recipes/my_merge.yml")
options = preset.to_h
```

### `Config`

`Ast::Merge::Recipe::Config` extends `Preset` with file-oriented recipe data:

- `template`
- `targets`
- `injection`
- `when_missing`

It also resolves template paths and expands target globs relative to the recipe file.

`Config` now normalizes `injection` into a shared partial-target contract so the runner can reason about partial merges without reparsing YAML shape details per parser family.

### `Runner`

`Ast::Merge::Recipe::Runner` executes a `Config` against target files.

In the stock `ast-merge` gem, the built-in runner supports parser-backed partial-template flows through:

- `parser: :markly`
- `parser: :commonmarker`
- `parser: :psych`

When parser selection is not passed directly:

- an explicitly configured recipe parser is honored automatically
- otherwise the stock runner defaults to `:markly` for backward compatibility

For other formats, the stable API in this gem is still `Preset#to_h`; callers pass those options to the format-specific merger they are already using.

### `ScriptLoader`

`Ast::Merge::Recipe::ScriptLoader` loads companion Ruby scripts referenced by a recipe.

A recipe named `my_recipe.yml` looks for scripts in a sibling directory named `my_recipe/`.

## Minimal preset example

```yaml
name: my_merge
parser: psych
merge:
  preference: destination
  add_missing: true
freeze_token: my-project
```

```ruby
preset = Ast::Merge::Recipe::Preset.load("recipes/my_merge.yml")
merger = Psych::Merge::SmartMerger.new(template, destination, **preset.to_h)
```

## Full recipe example

```yaml
name: gem_family_section
template: GEM_FAMILY_SECTION.md
targets:
  - README.md

injection:
  anchor:
    type: heading
    text: "/Gem Family/"
  position: replace
  boundary:
    type: heading
    same_or_shallower: true

merge:
  preference: template
  add_missing: true

when_missing: skip
```

```ruby
recipe = Ast::Merge::Recipe::Config.load(".merge-recipes/gem_family_section.yml")
runner = Ast::Merge::Recipe::Runner.new(recipe, dry_run: true, parser: :markly)
results = runner.run
```

## Shared partial-target contract

Recipe `injection` is modeled as exactly one partial-target shape at a time.

| Shared target kind | YAML shape | Meaning | Current stock runner support |
|---|---|---|---|
| `:navigable` | `anchor` + optional `boundary` + optional `position` | locate a structural region by node metadata and merge within that section | Markdown-family partial merges (`:markly`, `:commonmarker`) |
| `:key_path` | `key_path` | locate a hierarchical path inside a structured document | Psych/YAML partial merges (`:psych`) |

`key_path` is intentionally part of the shared `ast-merge` contract rather than a Psych-only escape hatch. Hierarchical path targeting is a cross-format pattern that can apply to YAML, XML, and other tree-shaped formats even when the concrete merger implementation remains format-specific.

Invalid mixed shapes are rejected early. In particular:

- do not combine `anchor`/`boundary` with `key_path` in one recipe
- `boundary` and `position` require `anchor`
- `key_path` cannot be empty

Programmatic callers can inspect the normalized contract through:

- `recipe.partial_target`
- `recipe.partial_target_kind`
- `recipe.navigable_partial_target?`
- `recipe.key_path_partial_target?`

## YAML key-path partial recipe example

```yaml
name: rubocop_excludes
template: rubocop_excludes.yml
targets:
  - .rubocop.yml

injection:
  key_path:
    - AllCops
    - Exclude

merge:
  preference: destination
  add_missing: true

when_missing: add
```

```ruby
recipe = Ast::Merge::Recipe::Config.load(".merge-recipes/rubocop_excludes.yml")
runner = Ast::Merge::Recipe::Runner.new(recipe, dry_run: true, parser: :psych)
results = runner.run
```

## Script references

Recipe values such as `signature_generator`, `node_typing`, and `add_missing` can point at Ruby files that return callables.

Example layout:

```text
recipes/
  gem_family_section.yml
  gem_family_section/
    signature_generator.rb
    heading_typing.rb
```

Example script:

```ruby
lambda do |node|
  next node unless node.respond_to?(:text)

  if node.text.include?("Gem Family")
    [:gem_family_heading]
  else
    node
  end
end
```

Inline lambda expressions are also supported by `ScriptLoader`.

## Anchor text matching

Anchor matching uses node `.text`, which is plain text rather than source markup.

For Markdown headings that means formatting is stripped:

| Source | `.text` |
|--------|---------|
| `` ### The `*-merge` Gem Family `` | `The *-merge Gem Family` |
| `[link text](url)` | `link text` |

Write anchor patterns against the plain-text form:

```yaml
anchor:
  type: heading
  text: "/\\*-merge Gem Family/"
```

## Markdown-specific recipe options

The built-in runner forwards these options to Markdown partial-template mergers when present:

- `merge.normalize_whitespace`
- `merge.rehydrate_link_references`

The stock runner does **not** apply any generic whitespace cleanup pass of its own after a smart merge. These options stay in the recipe model so callers can keep a single YAML representation even when execution happens elsewhere.

## Stock runner extension boundaries

The stable extension contract for downstream repos is:

1. add new parser-family partial-target shapes to `Ast::Merge::Recipe::Config`
2. normalize them through `partial_target` / `partial_target_kind`
3. dispatch them in `Ast::Merge::Recipe::Runner`
4. keep parser-specific merge behavior in the leaf format gem or family layer

This keeps `ast-merge` responsible for the cross-format contract and routing surface while leaving syntax-specific analysis and emission in the appropriate downstream implementation.

At the moment, the stock runner supports:

- Markdown-family partial recipes through `injection.anchor`, optional `injection.boundary`, and `injection.position`
- Psych/YAML partial recipes through `injection.key_path`

If a parser family needs a different partial target shape later, the recipe model can carry that target without forcing all formats into one anchor model.
