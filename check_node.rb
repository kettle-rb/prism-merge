require "prism"

code = <<~RUBY
  appraise "unlocked" do
    eval_gemfile "a.gemfile"
  end
RUBY

result = Prism.parse(code)
node = result.value.statements.body.first
puts "Node type: #{node.class}"
if node.respond_to?(:block)
  puts "Has block: #{!node.block.nil?}"
  puts "Block type: #{node.block.class}"
end
