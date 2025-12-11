# frozen_string_literal: true

RSpec.describe Prism::Merge::Comment::Line do
  describe "#magic_comment?" do
    it "detects frozen_string_literal magic comment" do
      line = described_class.new(text: "# frozen_string_literal: true", line_number: 1)
      expect(line.magic_comment?).to be true
    end

    it "detects encoding magic comment" do
      line = described_class.new(text: "# encoding: UTF-8", line_number: 1)
      expect(line.magic_comment?).to be true
    end

    it "detects coding magic comment (alias for encoding)" do
      line = described_class.new(text: "# coding: UTF-8", line_number: 1)
      expect(line.magic_comment?).to be true
    end

    it "detects warn_indent magic comment" do
      line = described_class.new(text: "# warn_indent: true", line_number: 1)
      expect(line.magic_comment?).to be true
    end

    it "detects shareable_constant_value magic comment" do
      line = described_class.new(text: "# shareable_constant_value: literal", line_number: 1)
      expect(line.magic_comment?).to be true
    end

    it "returns false for regular comments" do
      line = described_class.new(text: "# This is a regular comment", line_number: 1)
      expect(line.magic_comment?).to be false
    end
  end

  describe "#magic_comment_type" do
    it "returns the magic comment type" do
      line = described_class.new(text: "# frozen_string_literal: true", line_number: 1)
      expect(line.magic_comment_type).to eq(:frozen_string_literal)
    end

    it "returns nil for non-magic comments" do
      line = described_class.new(text: "# regular comment", line_number: 1)
      expect(line.magic_comment_type).to be_nil
    end
  end

  describe "#magic_comment_value" do
    it "extracts the value from magic comments" do
      line = described_class.new(text: "# frozen_string_literal: true", line_number: 1)
      expect(line.magic_comment_value).to eq("true")
    end

    it "handles encoding values" do
      line = described_class.new(text: "# encoding: UTF-8", line_number: 1)
      expect(line.magic_comment_value).to eq("UTF-8")
    end
  end

  describe "inheritance from Ast::Merge::Comment::Line" do
    it "has access to content method" do
      line = described_class.new(text: "# hello world", line_number: 1)
      expect(line.content).to eq("hello world")
    end

    it "has access to signature method" do
      line = described_class.new(text: "# Hello", line_number: 1)
      expect(line.signature).to eq([:comment_line, "hello"])
    end

    it "uses hash_comment style by default" do
      line = described_class.new(text: "# test", line_number: 1)
      expect(line.style.name).to eq(:hash_comment)
    end
  end
end

RSpec.describe Prism::Merge::Comment::Block do
  describe "#contains_magic_comment?" do
    it "returns true when block contains a magic comment" do
      children = [
        Prism::Merge::Comment::Line.new(text: "# frozen_string_literal: true", line_number: 1),
        Prism::Merge::Comment::Line.new(text: "# Regular comment", line_number: 2),
      ]
      block = described_class.new(children: children)
      expect(block.contains_magic_comment?).to be true
    end

    it "returns false when no magic comments present" do
      children = [
        Prism::Merge::Comment::Line.new(text: "# Just a comment", line_number: 1),
        Prism::Merge::Comment::Line.new(text: "# Another comment", line_number: 2),
      ]
      block = described_class.new(children: children)
      expect(block.contains_magic_comment?).to be false
    end
  end

  describe "#magic_comments" do
    it "returns all magic comment lines" do
      children = [
        Prism::Merge::Comment::Line.new(text: "# frozen_string_literal: true", line_number: 1),
        Prism::Merge::Comment::Line.new(text: "# encoding: UTF-8", line_number: 2),
        Prism::Merge::Comment::Line.new(text: "# Regular comment", line_number: 3),
      ]
      block = described_class.new(children: children)

      magic = block.magic_comments
      expect(magic.size).to eq(2)
      expect(magic.map(&:magic_comment_type)).to contain_exactly(:frozen_string_literal, :encoding)
    end
  end
end

RSpec.describe Prism::Merge::Comment::Parser do
  describe "#parse" do
    it "produces Comment::Line nodes" do
      lines = ["# frozen_string_literal: true"]
      nodes = described_class.parse(lines)

      expect(nodes.first).to be_a(Prism::Merge::Comment::Block)
      expect(nodes.first.children.first).to be_a(Prism::Merge::Comment::Line)
    end

    it "produces Comment::Block nodes" do
      lines = ["# First", "# Second"]
      nodes = described_class.parse(lines)

      expect(nodes.size).to eq(1)
      expect(nodes.first).to be_a(Prism::Merge::Comment::Block)
    end

    it "separates blocks by empty lines" do
      lines = ["# Block one", "", "# Block two"]
      nodes = described_class.parse(lines)

      expect(nodes.size).to eq(3)
      expect(nodes[0]).to be_a(Prism::Merge::Comment::Block)
      expect(nodes[1]).to be_a(Ast::Merge::Comment::Empty)
      expect(nodes[2]).to be_a(Prism::Merge::Comment::Block)
    end

    it "detects magic comments in blocks" do
      lines = ["# frozen_string_literal: true", "# Another comment"]
      nodes = described_class.parse(lines)

      expect(nodes.first.contains_magic_comment?).to be true
    end

    it "returns empty array for empty input" do
      expect(described_class.parse([])).to eq([])
    end

    it "handles non-comment content in comment-only context" do
      # This tests the else branch at line 61-62 in parser.rb
      # When a line doesn't match comment pattern, it's added as a generic line
      lines = ["# First comment", "not_a_comment", "# Another comment"]
      nodes = described_class.parse(lines)

      # Should produce blocks and a generic line node
      expect(nodes.size).to be >= 2
    end
  end
end

RSpec.describe Prism::Merge::Comment::Line, "additional coverage" do
  describe "#magic_comment_value edge cases" do
    it "returns nil when pattern doesn't match" do
      # Tests line 73 - early return when no pattern matches
      line = described_class.new(text: "# regular comment without colon", line_number: 1)
      expect(line.magic_comment_value).to be_nil
    end

    it "handles magic comment without value returns nil" do
      # Tests line 78-79 - magic comment patterns require a value
      # e.g., frozen_string_literal: requires true/false
      line = described_class.new(text: "# frozen_string_literal:", line_number: 1)
      value = line.magic_comment_value
      expect(value).to be_nil
    end

    it "handles magic comment with value" do
      # Tests the split and strip logic when pattern matches
      line = described_class.new(text: "# frozen_string_literal: true", line_number: 1)
      value = line.magic_comment_value
      expect(value).to eq("true")
    end
  end

  describe "#inspect" do
    it "includes magic comment info when present" do
      line = described_class.new(text: "# frozen_string_literal: true", line_number: 1)
      expect(line.inspect).to include("magic=")
      expect(line.inspect).to include("frozen_string_literal")
    end

    it "omits magic info for regular comments" do
      line = described_class.new(text: "# regular", line_number: 1)
      expect(line.inspect).not_to include("magic=")
    end
  end
end

RSpec.describe Prism::Merge::Comment::Block, "additional coverage" do
  describe "#inspect" do
    it "includes has_magic_comments when present" do
      children = [
        Prism::Merge::Comment::Line.new(text: "# frozen_string_literal: true", line_number: 1),
      ]
      block = described_class.new(children: children)
      expect(block.inspect).to include("has_magic_comments")
    end

    it "omits magic info when no magic comments" do
      children = [
        Prism::Merge::Comment::Line.new(text: "# regular", line_number: 1),
      ]
      block = described_class.new(children: children)
      expect(block.inspect).not_to include("has_magic_comments")
    end
  end
end
