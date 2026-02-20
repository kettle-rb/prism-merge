# AGENTS.md - prism-merge Development Guide

## 🎯 Project Overview

`prism-merge` is a **format-specific implementation of the `*-merge` gem family** for Ruby files. It provides intelligent Ruby file merging using AST analysis via the Prism parser.

**Core Philosophy**: Intelligent Ruby code merging that preserves structure, comments, and formatting while applying updates from templates.

**Repository**: https://github.com/kettle-rb/prism-merge
**Current Version**: 2.0.0
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Not Visible

**CRITICAL**: AI agents using `run_in_terminal` almost never see the command output. The terminal tool sends commands to a persistent Copilot terminal, but output is frequently lost or invisible to the agent.

**Workaround**: Always redirect output to a file in the project's local `tmp/` directory, then read it back with `read_file`:

```bash
bundle exec rspec spec/some_spec.rb > tmp/test_output.txt 2>&1
```

**NEVER** use `/tmp` or other system directories — always use the project's own `tmp/` directory.

### direnv Requires Separate `cd` Command

**CRITICAL**: Never chain `cd` with other commands via `&&`. The `direnv` environment won't initialize until after all chained commands finish. Run `cd` alone first:

✅ **CORRECT**:
```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/prism-merge
```
```bash
bundle exec rspec > tmp/test_output.txt 2>&1
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/prism-merge && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

Use `read_file`, `list_dir`, `grep_search`, `file_search` instead of terminal commands for gathering information. Only use terminal for running tests, installing dependencies, and git operations.

### grep_search Cannot Search Nested Git Projects

This project is a nested git project inside the `ast-merge` workspace. The `grep_search` tool **cannot** search inside it. Use `read_file` and `list_dir` instead.

### NEVER Pipe Test Commands Through head/tail

Always redirect to a file in `tmp/` instead of truncating output.

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

## 🔧 Development Workflows

### Running Tests

```bash
# Full suite (required for coverage thresholds)
bundle exec rspec

# Single file (disable coverage threshold check)
K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/prism/merge/smart_merger_spec.rb
```

**Note**: Always run commands in the project root (`/home/pboling/src/kettle-rb/ast-merge/vendor/prism-merge`). Allow `direnv` to load environment variables first by doing a plain `cd` before running commands.

### Coverage Reports

```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/prism-merge
bin/rake coverage && bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `.envrc`, loaded via `direnv allow`):
- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE=100` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH=82` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

### Code Quality

```bash
bundle exec rake reek
bundle exec rake rubocop_gradual
```

## 📝 Project Conventions

### API Conventions

#### SmartMerger API
- `merge` – Returns a **String** (the merged Ruby content)
- `merge_result` – Returns a **MergeResult** object
- `to_s` on MergeResult returns the merged content as a string

#### Ruby-Specific Features

**Statement-Level Merging**:
```ruby
merger = Prism::Merge::SmartMerger.new(template_rb, dest_rb)
result = merger.merge
```

**Freeze Blocks**:
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

This project uses `kettle-dev` for gem maintenance automation:

- **Rakefile**: Sourced from kettle-dev template
- **CI Workflows**: GitHub Actions and GitLab CI managed via kettle-dev
- **Releases**: Use `kettle-release` for automated release process

### Version Requirements
- Ruby >= 3.2.0 (gemspec), developed against Ruby 4.0.1 (`.tool-versions`)
- `ast-merge` >= 4.0.0 required
- `tree_haver` >= 5.0.3 required
- `prism` >= 1.6.0 required

## 🧪 Testing Patterns

### TreeHaver Dependency Tags

All spec files use TreeHaver RSpec dependency tags for conditional execution:

**Available tags**:
- `:prism_backend` – Requires Prism backend
- `:ruby_parsing` – Requires Ruby parser

✅ **CORRECT** – Use dependency tag on describe/context/it:
```ruby
RSpec.describe Prism::Merge::SmartMerger, :prism_backend do
  # Skipped if Prism not available
end

it "parses Ruby", :ruby_parsing do
  # Skipped if no Ruby parser available
end
```

❌ **WRONG** – Never use manual skip checks:
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
| `.envrc` | Coverage thresholds and environment configuration |

## 🚀 Common Tasks

```bash
# Run all specs with coverage
bundle exec rake spec

# Generate coverage report
bundle exec rake coverage

# Check code quality
bundle exec rake reek
bundle exec rake rubocop_gradual

# Prepare and release
kettle-changelog && kettle-release
```

## 🌊 Integration Points

- **`ast-merge`**: Inherits base classes (`SmartMergerBase`, `FileAnalyzable`, etc.)
- **`tree_haver`**: Wraps Prism parser in unified TreeHaver interface
- **`prism`**: Fast, error-tolerant Ruby parser
- **RSpec**: Full integration via `ast/merge/rspec` and `tree_haver/rspec`
- **SimpleCov**: Coverage tracked for `lib/**/*.rb`; spec directory excluded

## 💡 Key Insights

1. **Section-based merging**: Ruby files are merged by top-level statements (classes, methods, constants)
2. **Magic comment handling**: Ruby magic comments are detected and positioned correctly in output
3. **Comment preservation**: Prism provides rich comment information; we preserve all comments
4. **Error tolerance**: Prism can parse Ruby with syntax errors; we detect and report them
5. **Freeze blocks use `# prism-merge:freeze`**: Language-specific comment syntax
6. **Signature matching**: Methods matched by name, classes by name, gems by name in Gemfile
7. **No FileAligner/ConflictResolver vestigial**: prism-merge was refactored to remove these unused components

## 🚫 Common Pitfalls

1. **NEVER assume valid Ruby**: Use `FileAnalysis#valid?` to check parse success
2. **NEVER use manual skip checks** – Use dependency tags (`:prism_backend`, `:ruby_parsing`)
3. **Magic comments are Ruby-specific** – They belong in prism-merge, not ast-merge
4. **Do NOT load vendor gems** – They are not part of this project; they do not exist in CI
5. **Use `tmp/` for temporary files** – Never use `/tmp` or other system directories
6. **Do NOT chain `cd` with `&&`** – Run `cd` as a separate command so `direnv` loads ENV

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
