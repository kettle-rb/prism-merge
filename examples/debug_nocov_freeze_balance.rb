#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Balanced freeze/unfreeze block should NOT freeze subsequent code node
#
# Root cause investigation for two bugs observed when merging Rakefile:
#
# Bug 1: Opening `# :nocov:` missing from merged output
#   - The IfNode (require "bundler/gem_tasks" if ...) is incorrectly detected
#     as frozen because `# kettle-jem:freeze` appears in its leading comments.
#   - The balanced freeze/unfreeze block at lines 3-7 of the dest Rakefile is
#     a standalone directive for that comment chunk, NOT a node-level freeze.
#   - Fix: frozen_node? must only trigger on UNBALANCED freeze markers
#     (a freeze not followed by a matching unfreeze in the same leading comment block).
#
# Bug 2: Extra blank line before closing `# :nocov:`
#   - Once Bug 1 is fixed (IfNode becomes template-wins), the blank that was
#     emitted by emit_node's dest-side trailing gap handling should disappear.

WORKSPACE_ROOT = File.expand_path("../..", __dir__)
ENV["KETTLE_RB_DEV"] = WORKSPACE_ROOT unless ENV.key?("KETTLE_RB_DEV")

require "bundler/inline"

gemfile do
  source "https://gem.coop"
  require File.expand_path("nomono/lib/nomono/bundler", WORKSPACE_ROOT)

  eval_nomono_gems(
    gems: %w[ast-merge tree_haver prism-merge kettle-jem],
    prefix: "KETTLE_RB",
    path_env: "KETTLE_RB_DEV",
    vendored_gems_env: "VENDORED_GEMS",
    vendor_gem_dir_env: "VENDOR_GEM_DIR",
    debug_env: "KETTLE_DEV_DEBUG"
  )
end

require "prism/merge"

puts "=" * 70
puts "Test 1: Balanced freeze/unfreeze block — IfNode should NOT be frozen"
puts "=" * 70

template1 = <<~RUBY
  # frozen_string_literal: true

  # :nocov:
  require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
  # :nocov:

  desc "hello"
  task :hello do
    puts "hello"
  end
RUBY

dest1 = <<~RUBY
  # frozen_string_literal: true

  # kettle-jem:freeze
  # Custom header to preserve
  # kettle-jem:unfreeze

  require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?

  desc "hello"
  task :hello do
    puts "hello"
  end
RUBY

analysis1 = Prism::Merge::FileAnalysis.new(dest1, freeze_token: "kettle-jem")
analysis1.send(:attach_comments_safely!)
stmts1 = analysis1.send(:extract_and_integrate_all_nodes)

if_node1 = stmts1.find { |s| s.is_a?(Prism::IfNode) }

puts "\nDest statements:"
stmts1.each_with_index { |s, i| puts "  [#{i}] #{s.class}" }

puts "\nIfNode found: #{if_node1.class}"
puts "frozen? => #{analysis1.send(:frozen_node?, if_node1)}"
if if_node1.respond_to?(:location) && if_node1.location.respond_to?(:leading_comments)
  lc = if_node1.location.leading_comments
  puts "Leading comment count: #{lc.size}"
  lc.each { |c| puts "  #{c.location.start_line}: #{c.slice.rstrip}" }
end

puts "\nMerge result (with tracing):"

# Patch filtered_leading_comments_for to trace calls for the IfNode
module TraceLeadingComments
  def filtered_leading_comments_for(node, source)
    result = super
    if node.is_a?(Prism::IfNode)
      puts "  [trace] filtered_leading_comments_for IfNode source=#{source}"
      puts "    comments: #{result[:comments].map { |c| c.slice.rstrip }.inspect}"
      puts "    last_skipped_line: #{result[:last_skipped_line].inspect}"
    end
    result
  end
end
Prism::Merge::WrapperCommentSupport.prepend(TraceLeadingComments)

module TraceEmitLeading
  def emit_leading_comments(result, comments, analysis:, source:, decision:, prev_comment_line: nil)
    unless comments.empty?
      puts "  [trace] emit_leading_comments source=#{source} comments=#{comments.map { |c| c.slice.rstrip }.inspect}"
      puts "    caller: #{caller.first(3).map { |l| l.split("/").last(2).join("/") }.inspect}"
    end
    super
  end
end
Prism::Merge::SmartMerger.prepend(TraceEmitLeading)

result1 = Prism::Merge::SmartMerger.new(template1, dest1, preference: :template, freeze_token: "kettle-jem").merge_result
puts result1.to_s
puts "\nExpected to contain '# :nocov:' before the require line: #{result1.to_s.include?("# :nocov:\nrequire")}"
puts "Expected to NOT have double blank before first '# :nocov:': #{!result1.to_s.include?("\n\n\n# :nocov:")}"

puts
puts "=" * 70
puts "Test 2: Unbalanced freeze marker — IfNode SHOULD be frozen"
puts "=" * 70

dest2 = <<~RUBY
  # frozen_string_literal: true

  # kettle-jem:freeze
  # This is a frozen-node annotation (no matching unfreeze)
  require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
RUBY

analysis2 = Prism::Merge::FileAnalysis.new(dest2, freeze_token: "kettle-jem")
analysis2.send(:attach_comments_safely!)
stmts2 = analysis2.send(:extract_and_integrate_all_nodes)

if_node2 = stmts2.find { |s|
  s.is_a?(Prism::IfNode) || (s.respond_to?(:unwrap) && s.unwrap.is_a?(Prism::IfNode))
}
puts "IfNode class: #{if_node2.class}"
puts "frozen? => #{analysis2.send(:frozen_node?, if_node2)}"
puts "Expected: true"

puts
puts "=" * 70
puts "Test 3: Full Rakefile merge — :nocov: placement"
puts "=" * 70

rakefile_template = File.read(File.join(WORKSPACE_ROOT, "kettle-jem/template/Rakefile.example"))
rakefile_dest = File.read(File.join(WORKSPACE_ROOT, "ast-merge/Rakefile"))

begin
  require "kettle/jem"
  merged = Kettle::Jem::SourceMerger.apply(strategy: :merge, src: rakefile_template, dest: rakefile_dest, path: "Rakefile")
rescue LoadError, NameError => e
  puts "kettle-jem not available: #{e.message}"
  merged = Prism::Merge::SmartMerger.new(rakefile_template, rakefile_dest, preference: :template, freeze_token: "kettle-jem").merge_result.to_s
end

# Find the lines around bundler/gem_tasks
lines = merged.split("\n")
idx = lines.index { |l| l.include?("bundler/gem_tasks") }
if idx
  context_start = [0, idx - 3].max
  context_end = [lines.size - 1, idx + 3].min
  puts "Context around 'bundler/gem_tasks' (lines #{context_start + 1}..#{context_end + 1}):"
  lines[context_start..context_end].each_with_index do |l, i|
    puts "  #{context_start + i + 1}: #{l.inspect}"
  end

  opening_nocov_line = lines[0...idx].rindex { |l| l.strip == "# :nocov:" }
  closing_nocov_line = lines[(idx + 1)..].index { |l| l.strip == "# :nocov:" }
  closing_nocov_line += idx + 1 if closing_nocov_line

  puts "\nOpening '# :nocov:' before require: line #{opening_nocov_line ? opening_nocov_line + 1 : "MISSING"}"
  puts "Closing '# :nocov:' after require:  line #{closing_nocov_line ? closing_nocov_line + 1 : "MISSING"}"

  puts "\nBug 1 FIXED (opening :nocov: present):  #{!opening_nocov_line.nil?}"
  puts "Bug 2 FIXED (no extra blank after IfNode): #{closing_nocov_line && (lines[idx + 1]&.strip == "# :nocov:")}"
else
  puts "bundler/gem_tasks line not found in merged output"
end
