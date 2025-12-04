# # frozen_string_literal: true

# RSpec.describe Prism::Merge::FileAnalysis do
#   describe "#initialize" do
#     it "parses Ruby content" do
#       content = <<~RUBY
#         # frozen_string_literal: true

#         def hello
#           puts "world"
#         end
#       RUBY

#       analysis = described_class.new(content)

#       expect(analysis.valid?).to be true
#       expect(analysis.content).to eq(content)
#       expect(analysis.lines.length).to eq(5)
#     end
#   end

#   describe "#statements" do
#     it "extracts top-level statements" do
#       content = <<~RUBY
#         def hello
#           puts "world"
#         end

#         def goodbye
#           puts "farewell"
#         end
#       RUBY

#       analysis = described_class.new(content)

#       expect(analysis.statements.length).to eq(2)
#       expect(analysis.statements[0]).to be_a(Prism::DefNode)
#       expect(analysis.statements[1]).to be_a(Prism::DefNode)
#     end
#   end

#   describe "#freeze_blocks" do
#     it "extracts freeze block information" do
#       content = <<~RUBY
#         # Regular comment

#         # kettle-dev:freeze
#         # Custom content
#         gem "custom"
#         # kettle-dev:unfreeze

#         gem "standard"
#       RUBY

#       analysis = described_class.new(content, freeze_token: "kettle-dev")

#       expect(analysis.freeze_blocks.length).to eq(1)
#       freeze_block = analysis.freeze_blocks.first
#       expect(freeze_block.start_marker).to eq("# kettle-dev:freeze")
#       expect(freeze_block.slice).to include("# Custom content")
#       expect(freeze_block.slice).to include('gem "custom"')
#     end

#     it "returns empty array when no freeze blocks" do
#       content = "def hello; end"
#       analysis = described_class.new(content)

#       expect(analysis.freeze_blocks).to be_empty
#     end
#   end

#   describe "#in_freeze_block?" do
#     it "identifies lines within freeze blocks" do
#       content = <<~RUBY
#         line 1
#         # kettle-dev:freeze
#         line 3
#         # kettle-dev:unfreeze
#         line 5
#       RUBY

#       analysis = described_class.new(content, freeze_token: "kettle-dev")

#       expect(analysis.in_freeze_block?(1)).to be false
#       expect(analysis.in_freeze_block?(2)).to be true
#       expect(analysis.in_freeze_block?(3)).to be true
#       expect(analysis.in_freeze_block?(4)).to be true
#       expect(analysis.in_freeze_block?(5)).to be false
#     end
#   end

#   describe "#signature_at" do
#     it "returns signature for a statement" do
#       content = <<~RUBY
#         def hello
#           puts "world"
#         end
#       RUBY

#       analysis = described_class.new(content)
#       sig = analysis.signature_at(0)

#       expect(sig).to be_a(Array)
#       expect(sig.first).to eq(:DefNode)
#     end

#     it "returns nil for out of bounds index" do
#       content = "def hello; end"
#       analysis = described_class.new(content)

#       expect(analysis.signature_at(99)).to be_nil
#       expect(analysis.signature_at(-1)).to be_nil
#     end
#   end

#   describe "#normalized_line" do
#     it "returns stripped line content" do
#       content = "  hello world  \n"
#       analysis = described_class.new(content)

#       expect(analysis.normalized_line(1)).to eq("hello world")
#     end

#     it "returns nil for invalid line numbers" do
#       content = "hello"
#       analysis = described_class.new(content)

#       expect(analysis.normalized_line(0)).to be_nil
#       expect(analysis.normalized_line(99)).to be_nil
#     end
#   end

#   describe "#nodes_with_comments" do
#     it "extracts nodes with their associated comments" do
#       content = <<~RUBY
#         # Leading comment
#         def hello # inline comment
#           puts "world"
#         end
#       RUBY

#       analysis = described_class.new(content)
#       nodes = analysis.nodes_with_comments

#       # Now we get 2 nodes: the CommentNode for the leading comment,
#       # and the DefNode with an inline comment
#       expect(nodes.length).to eq(2)

#       # First node should be the CommentNode
#       comment_node_info = nodes.first
#       expect(comment_node_info[:node]).to be_a(Prism::Merge::CommentNode)

#       # Second node should be the DefNode
#       def_node_info = nodes.last
#       expect(def_node_info[:node]).to be_a(Prism::DefNode)
#       expect(def_node_info[:leading_comments].length).to eq(0) # Comment is now a separate node
#       expect(def_node_info[:inline_comments].length).to eq(1)
#     end
#   end
# end
