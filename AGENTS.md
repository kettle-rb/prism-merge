# AGENTS.md - Development Guide

## 🎯 Project Overview

**Minimum Supported Ruby**: See the gemspec `required_ruby_version` constraint.
**Local Development Ruby**: See `.tool-versions` for the version used in local development (typically the latest stable Ruby).

**Core Philosophy**: Intelligent Ruby code merging that preserves structure, comments, and formatting while applying updates from templates.

**Repository**: https://github.com/kettle-rb/prism-merge
**Current Version**: 2.0.0
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Available, but Each Command Is Isolated

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

✅ **CORRECT** — If you need shell syntax first, load the environment in the same command:

### Use `mise` for Project Environment

**CRITICAL**: The canonical project environment lives in `mise.toml`, with local overrides in `.env.local` loaded via `dotenvy`.

⚠️ **Watch for trust prompts**: After editing `mise.toml` or `.env.local`, `mise` may require trust to be refreshed before commands can load the project environment. Until that trust step is handled, commands can appear hung or produce no output, which can look like terminal access is broken.

**Recovery rule**: If a `mise exec` command goes silent or appears hung, assume `mise trust` is the first thing to check. Recover by running:

```bash
mise trust -C /home/pboling/src/kettle-rb/prism-merge
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rspec
```

```bash
mise trust -C /path/to/project
mise exec -C /path/to/project -- bundle exec rspec
```

Do this before spending time on unrelated debugging; in this workspace pattern, silent `mise` commands are usually a trust problem first.

```bash
mise trust -C /home/pboling/src/kettle-rb/prism-merge
```

✅ **CORRECT**:
```bash
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rspec
```

✅ **CORRECT**:
```bash
eval "$(mise env -C /home/pboling/src/kettle-rb/prism-merge -s bash)" && bundle exec rspec
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/prism-merge
bundle exec rspec
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/prism-merge && bundle exec rspec
```

```bash
cd /path/to/project
bundle exec rspec
```

❌ **WRONG** — A chained `cd` does not give directory-change hooks time to update the environment:

```bash
cd /path/to/project && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

### Forward Compatibility with `**options`

**CRITICAL**: All constructors and public API methods that accept keyword arguments MUST include `**options` as the final parameter for forward compatibility.

### Workspace layout

## 🏗️ Architecture

### Toolchain Dependencies

This gem is part of the **kettle-rb** ecosystem. Key development tools:

### NEVER Pipe Test Commands Through head/tail

When you do run tests, keep the full output visible so you can inspect failures completely.

## 🏗️ Architecture: Format-Specific Implementation

### What prism-merge Provides

- **`Prism::Merge::SmartMerger`** – Ruby-specific SmartMerger implementation
- **`Prism::Merge::FileAnalysis`** – Ruby file analysis with statement extraction
- **`Prism::Merge::NodeWrapper`** – Wrapper for Prism AST nodes
- **`Prism::Merge::MergeResult`** – Ruby-specific merge result
- **`Prism::Merge::ConflictResolver`** – Ruby conflict resolution
- **`Prism::Merge::FreezeNode`** – Ruby freeze block support
- **`Prism::Merge::Comment::*`** – Ruby comment classes with magic comment detection
- **`Prism::Merge::DebugLogger`** – Prism-specific debug logging

### Key Dependencies

| Gem | Role |
|-----|------|
| `ast-merge` (~> 4.0) | Base classes and shared infrastructure |
| `tree_haver` (~> 5.0) | Unified parser adapter (wraps Prism) |
| `prism` (~> 1.6) | Ruby parser |
| `version_gem` (~> 1.1) | Version management |

### Parser Backend

prism-merge uses the Prism parser exclusively via TreeHaver's `:prism_backend`:

| Backend | Parser | Platform | Notes |
|---------|--------|----------|-------|
| `:prism_backend` | Prism | All Ruby platforms | Fast, error-tolerant Ruby parser |

| Tool | Purpose |
|------|---------|
| `kettle-dev` | Development dependency: Rake tasks, release tooling, CI helpers |
| `kettle-test` | Test infrastructure: RSpec helpers, stubbed_env, timecop |
| `kettle-jem` | Template management and gem scaffolding |

### Executables (from kettle-dev)

| Executable | Purpose |
|-----------|---------|
| `kettle-release` | Full gem release workflow |
| `kettle-pre-release` | Pre-release validation |
| `kettle-changelog` | Changelog generation |
| `kettle-dvcs` | DVCS (git) workflow automation |
| `kettle-commit-msg` | Commit message validation |
| `kettle-check-eof` | EOF newline validation |

## 📁 Project Structure

```
lib/prism/merge/
├── smart_merger.rb          # Main SmartMerger implementation
├── file_analysis.rb         # Ruby file analysis
├── node_wrapper.rb          # AST node wrapper for Prism nodes
├── merge_result.rb          # Merge result object
├── conflict_resolver.rb     # Conflict resolution
├── freeze_node.rb           # Freeze block support
├── comment/                 # Ruby-specific comment handling
│   ├── magic.rb            # Magic comment detection
│   └── parser.rb           # Comment parser
├── debug_logger.rb          # Debug logging
└── version.rb

spec/prism/merge/
├── smart_merger_spec.rb
├── file_analysis_spec.rb
├── node_wrapper_spec.rb
└── integration/
```

```
lib/
├── <gem_namespace>/           # Main library code
│   └── version.rb             # Version constant (managed by kettle-release)
spec/
├── fixtures/                  # Test fixture files (NOT auto-loaded)
├── support/
│   ├── classes/               # Helper classes for specs
│   └── shared_contexts/       # Shared RSpec contexts
├── spec_helper.rb             # RSpec configuration (loaded by .rspec)
gemfiles/
├── modular/                   # Modular Gemfile components
│   ├── coverage.gemfile       # SimpleCov dependencies
│   ├── debug.gemfile          # Debugging tools
│   ├── documentation.gemfile  # YARD/documentation
│   ├── optional.gemfile       # Optional dependencies
│   ├── rspec.gemfile          # RSpec testing
│   ├── style.gemfile          # RuboCop/linting
│   └── x_std_libs.gemfile     # Extracted stdlib gems
├── ruby_*.gemfile             # Per-Ruby-version Appraisal Gemfiles
└── Appraisal.root.gemfile     # Root Gemfile for Appraisal builds
.git-hooks/
├── commit-msg                 # Commit message validation hook
├── prepare-commit-msg         # Commit message preparation
├── commit-subjects-goalie.txt # Commit subject prefix filters
└── footer-template.erb.txt    # Commit footer ERB template
```

## 🔧 Development Workflows

### Running Commands

Always make commands self-contained. Use `mise exec -C /home/pboling/src/kettle-rb/prism-merge -- ...` so the command gets the project environment in the same invocation.
If the command is complicated write a script in local tmp/ and then run the script.

### Running Tests

Full suite spec runs:

```bash
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rspec
```

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

For single file, targeted, or partial spec runs the coverage threshold **must** be disabled.
Use the `K_SOUP_COV_MIN_HARD=false` environment variable to disable hard failure:

```bash
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/prism/merge/smart_merger_spec.rb
```

```bash
mise exec -C /path/to/project -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/path/to/spec.rb
```

### Coverage Reports

```bash
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bin/rake coverage
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bin/kettle-soup-cover -d
```

```ruby
# kettle-jem:freeze
# ... custom code preserved across template runs ...
# kettle-jem:unfreeze
```

### Modular Gemfile Architecture

Gemfiles are split into modular components under `gemfiles/modular/`. Each component handles a specific concern (coverage, style, debug, etc.). The main `Gemfile` loads these modular components via `eval_gemfile`.

```bash
mise exec -C /path/to/project -- bin/rake coverage
mise exec -C /path/to/project -- bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `mise.toml`, with local overrides in `.env.local`):
❌ **AVOID** when possible:

- `run_in_terminal` for information gathering

Only use terminal for:

- Running tests (`bundle exec rspec`)
- Installing dependencies (`bundle install`)
- Simple commands that do not require much shell escaping
- Running scripts (prefer writing a script over a complicated command with shell escaping)

### Code Quality

```bash
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rake reek
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rake rubocop_gradual
```

```bash
mise exec -C /path/to/project -- bundle exec rake reek
mise exec -C /path/to/project -- bundle exec rubocop-gradual
```

### Releasing

```bash
bin/kettle-pre-release    # Validate everything before release
bin/kettle-release        # Full release workflow
```

## 📝 Project Conventions

### API Conventions

#### SmartMerger API

### Test Infrastructure

- Uses `kettle-test` for RSpec helpers (stubbed_env, block_is_expected, silent_stream, timecop)
- Uses `Dir.mktmpdir` for isolated filesystem tests
- Spec helper is loaded by `.rspec` — never add `require "spec_helper"` to spec files

#### Ruby-Specific Features

**Statement-Level Merging**:
```ruby
merger = Prism::Merge::SmartMerger.new(template_rb, dest_rb)
result = merger.merge
```

### Freeze Block Preservation

Template updates preserve custom code wrapped in freeze blocks:

```ruby
# prism-merge:freeze
CUSTOM_CONSTANT = "don't override"
# prism-merge:unfreeze

class MyClass
end
```

**Magic Comment Preservation**:
```ruby
# frozen_string_literal: true
# encoding: utf-8
# warn_indent: true

# Magic comments are preserved and properly positioned
```

**Section-Based Merging**:
```ruby
class MyClass
  # Template sections
  def template_method
  end
  
  # Destination customizations
  def custom_method
  end
end
```

### kettle-dev Tooling

This project is a **RubyGem** managed with the [kettle-rb](https://github.com/kettle-rb) toolchain.

- **Rakefile**: Sourced from kettle-dev template
- **CI Workflows**: GitHub Actions and GitLab CI managed via kettle-dev
- **Releases**: Use `kettle-release` for automated release process

### Version Requirements

- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

## 🧪 Testing Patterns

### TreeHaver Dependency Tags

### Environment Variable Helpers

```ruby
before do
  stub_env("MY_ENV_VAR" => "value")
end

before do
  hide_env("HOME", "USER")
end
```

### Dependency Tags

Use dependency tags to conditionally skip tests when optional dependencies are not available:

**Available tags**:
- `:prism_backend` – Requires Prism backend
- `:ruby_parsing` – Requires Ruby parser

✅ **CORRECT** — Run self-contained commands with `mise exec`:

```ruby
RSpec.describe Prism::Merge::SmartMerger, :prism_backend do
  # Skipped if Prism not available
end

it "parses Ruby", :ruby_parsing do
  # Skipped if no Ruby parser available
end
```

```bash
eval "$(mise env -C /path/to/project -s bash)" && bundle exec rspec
```

❌ **WRONG** — Do not rely on a previous command changing directories:

```ruby
before do
  skip "Requires Prism" unless defined?(Prism)  # DO NOT DO THIS
end
```

### Shared Examples

prism-merge uses shared examples from `ast-merge`:

```ruby
it_behaves_like "Ast::Merge::FileAnalyzable"
it_behaves_like "Ast::Merge::ConflictResolverBase"
it_behaves_like "a reproducible merge", "scenario_name", { preference: :template }
```

## 🔍 Critical Files

| File | Purpose |
|------|---------|
| `lib/prism/merge/smart_merger.rb` | Main Ruby SmartMerger implementation |
| `lib/prism/merge/file_analysis.rb` | Ruby file analysis and statement extraction |
| `lib/prism/merge/node_wrapper.rb` | Prism node wrapper with Ruby-specific methods |
| `lib/prism/merge/comment/magic.rb` | Magic comment detection and handling |
| `lib/prism/merge/debug_logger.rb` | Prism-specific debug logging |
| `spec/spec_helper.rb` | Test suite entry point |
| `mise.toml` | Shared development environment defaults |

## 🚀 Common Tasks

```bash
# Run all specs with coverage
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rake spec

# Generate coverage report
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rake coverage

# Check code quality
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rake reek
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- bundle exec rake rubocop_gradual

# Prepare and release
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- kettle-changelog
mise exec -C /home/pboling/src/kettle-rb/prism-merge -- kettle-release
```

## 🌊 Integration Points

✅ **PREFERRED** — Use internal tools:

- `grep_search` instead of `grep` command
- `file_search` instead of `find` command
- `read_file` instead of `cat` command
- `list_dir` instead of `ls` command
- `replace_string_in_file` or `create_file` instead of `sed` / manual editing

## 💡 Key Insights

1. **Section-based merging**: Ruby files are merged by top-level statements (classes, methods, constants)
2. **Magic comment handling**: Ruby magic comments are detected and positioned correctly in output
3. **Comment preservation**: Prism provides rich comment information; we preserve all comments
4. **Error tolerance**: Prism can parse Ruby with syntax errors; we detect and report them
5. **Freeze blocks use `# prism-merge:freeze`**: Language-specific comment syntax
6. **Signature matching**: Methods matched by name, classes by name, gems by name in Gemfile
7. **No FileAligner/ConflictResolver vestigial**: prism-merge was refactored to remove these unused components

```ruby
RSpec.describe SomeClass, :prism_merge do
  # Skipped if prism-merge is not available
end
```

## 🚫 Common Pitfalls

1. **NEVER assume valid Ruby**: Use `FileAnalysis#valid?` to check parse success
2. **NEVER use manual skip checks** – Use dependency tags (`:prism_backend`, `:ruby_parsing`)
3. **Magic comments are Ruby-specific** – They belong in prism-merge, not ast-merge
4. **Do NOT load vendor gems** – They are not part of this project; they do not exist in CI
5. **Use `tmp/` for temporary files** – Never use `/tmp` or other system directories
6. **Do NOT expect `cd` to persist** – Every terminal command is isolated; use a self-contained `mise exec -C ... -- ...` invocation.
7. **Do NOT rely on prior shell state** – Previous `cd`, `export`, aliases, and functions are not available to the next command.

## 🔧 Ruby-Specific Notes

### Node Types in Prism

```ruby
Prism::CallNode           # Method calls (gem "example")
Prism::ClassNode          # Class definitions
Prism::ModuleNode         # Module definitions
Prism::DefNode            # Method definitions
Prism::ConstantWriteNode  # CONSTANT = value
Prism::BlockNode          # Blocks { }
```

### Merge Behavior

- **Classes**: Matched by class name; bodies merged recursively
- **Methods**: Matched by method name; entire method replaced (no body merge)
- **Gem calls**: Matched by gem name in Gemfile/gemspec
- **Constants**: Matched by constant name
- **Comments**: Preserved when attached to statements
- **Freeze blocks**: Protect customizations from template updates
- **Magic comments**: Always placed at top of file in correct order

### Magic Comments

```ruby
# Frozen string literal (should be first)
# frozen_string_literal: true

# Encoding (should be second)
# encoding: utf-8

# Warnings
# warn_indent: true
# warn_past_scope: true

# Shareable constant value
# shareable_constant_value: literal
```

### Section-Based Merging Example

```ruby
# Template:
class MyClass
  def template_method
    "from template"
  end
end

# Destination:
class MyClass
  def custom_method
    "custom"
  end
end

# Result (preference: :destination):
class MyClass
  def custom_method  # Destination kept
    "custom"
  end
  
  def template_method  # Template added
    "from template"
  end
end
```

1. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.
