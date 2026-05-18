# Test Organization

## Backend-Aware Testing

The bash-merge test suite is organized to test behavior across all available tree-sitter backends:

- **MRI** - `ruby_tree_sitter` gem (C extension, MRI only)
- **FFI** - FFI bindings to libtree-sitter
- **Rust** - `tree_stump` gem (Rust extension via Magnus)
- **Java** - `jtreesitter` (Java library for JRuby)

### Structure

```
spec/
├── support/
│   ├── shared_examples/
│   │   ├── file_analysis_examples.rb    # ALL FileAnalysis tests
│   │   └── smart_merger_examples.rb     # ALL SmartMerger tests
│   └── dependency_tags.rb                # RSpec tags from tree_haver
│
├── bash/merge/
│   ├── file_analysis_spec.rb            # Runs shared examples on all backends
│   ├── smart_merger_spec.rb             # Runs shared examples on all backends
│   ├── comment_tracker_spec.rb          # Unit tests for CommentTracker
│   ├── merge_result_spec.rb             # Unit tests for MergeResult
│   └── ...                               # Other unit test files
```

### Key Principle: ALL Tests in Shared Examples

**IMPORTANT**: For classes that depend on tree-sitter backends (FileAnalysis, SmartMerger), ALL tests must be in shared examples. There are no "legacy" or "quick" test files - every test runs on every backend.

### Shared Examples Pattern

Each shared example is parameterized and backend-agnostic:

```ruby
RSpec.shared_examples "bash source parsing" do |expected_backend:|
  it "parses successfully" do
    # Test implementation
  end
end

```

Backend-specific contexts use `TreeHaver.with_backend` to select the backend:

```ruby
# :auto backend - uses whatever is available (default behavior)
context "with :auto backend", :bash_grammar do
  it_behaves_like "bash source parsing", expected_backend: :auto
end

# Explicit backend selection
context "with MRI backend", :bash_grammar, :mri_backend do
  around do |example|
    TreeHaver.with_backend(:mri) do
      example.run
    end
  end

  it_behaves_like "bash source parsing", expected_backend: :mri
end

```

### RSpec Tags

Tests are tagged to run only when dependencies are available:

- `:mri_backend` - Requires `ruby_tree_sitter` gem
- `:ffi_backend` - Requires FFI and libtree-sitter
- `:rust_backend` - Requires `tree_stump` gem
- `:java_backend` - Requires JRuby and jtreesitter
- `:bash_grammar` - Requires tree-sitter-bash grammar

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run only MRI backend tests
bundle exec rspec --tag mri_backend

# Run only Java backend tests (on JRuby)
jruby -S bundle exec rspec --tag java_backend

# Run only FFI backend tests
bundle exec rspec --tag ffi_backend

# Run backend-specific tests
bundle exec rspec spec/bash/merge/file_analysis_spec.rb
bundle exec rspec spec/bash/merge/smart_merger_spec.rb

# Run :auto backend tests (whatever is available)
bundle exec rspec --tag bash_grammar
```

### Adding New Tests

When adding new tests for backend-dependent classes:

1. **Add to shared examples** - All tests go in `spec/support/shared_examples/*.rb`
2. **Include in ALL backend contexts** - Add `it_behaves_like` to ALL contexts (`:auto`, `:mri_backend`, `:ffi_backend`, `:rust_backend`, `:java_backend`)
3. **Handle backend differences** - Use conditional skips for unsupported operations
4. **Document limitations** - Add comments explaining backend-specific behavior

Example:

```ruby
# In shared_examples/file_analysis_examples.rb
RSpec.shared_examples "new feature test" do
  it "does something" do
    result = analysis.new_feature

    if result.nil?
      skip "Backend does not support new_feature"
    else
      expect(result).to be_truthy
    end
  end
end

# In file_analysis_spec.rb (ALL backend contexts)
context "with :auto backend", :bash_grammar do
  it_behaves_like "new feature test"
end

context "with MRI backend", :bash_grammar, :mri_backend do
  # ...existing code...
  it_behaves_like "new feature test"
end

# ... repeat for FFI, Rust, and Java backends
```

## Benefits

1. **Complete Coverage** - Every backend gets the same comprehensive test suite
2. **Early Detection** - Backend-specific issues are caught in CI
3. **Clear Expectations** - Each backend's capabilities are documented
4. **Maintainability** - Shared examples reduce duplication
5. **Flexibility** - Easy to add new backends or skip broken tests
6. **Debugging** - Clear skip messages explain why tests don't run

## Non-Backend-Dependent Tests

For classes that don't depend on tree-sitter backends (like CommentTracker, MergeResult, etc.), regular unit test files in `spec/bash/merge/` are fine. They don't need shared examples or backend contexts.
