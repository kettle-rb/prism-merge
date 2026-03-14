# frozen_string_literal: true

RSpec.describe Prism::Merge::RecursiveMergePolicy do
  def build_merger(template, dest, preference: :template, **options)
    Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
  end

  def first_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  describe "#should_merge?" do
    it "does not recursively merge single-line class wrappers" do
      source = <<~RUBY
        class Example; def shared; :value; end; end
      RUBY

      merger = build_merger(source, source)
      policy = described_class.new(merger: merger)

      expect(
        policy.should_merge?(template_node: first_node(merger, :template), dest_node: first_node(merger, :destination)),
      ).to be(false)
    end

    it "does not recursively merge single-line block wrappers" do
      source = <<~RUBY
        task do |task_name| puts task_name end
      RUBY

      merger = build_merger(source, source)
      policy = described_class.new(merger: merger)

      expect(
        policy.should_merge?(template_node: first_node(merger, :template), dest_node: first_node(merger, :destination)),
      ).to be(false)
    end

    it "still recursively merges multiline class wrappers" do
      source = <<~RUBY
        class Example
          def shared
            :value
          end
        end
      RUBY

      merger = build_merger(source, source)
      policy = described_class.new(merger: merger)

      expect(
        policy.should_merge?(template_node: first_node(merger, :template), dest_node: first_node(merger, :destination)),
      ).to be(true)
    end
  end

  describe "inline wrapper regression" do
    it "treats single-line class wrappers atomically so they are not emitted twice" do
      template = <<~RUBY
        class Example; def shared; :template; end; end
      RUBY

      dest = <<~RUBY
        class Example; def shared; :destination; end; def custom; :custom; end; end
      RUBY

      result = build_merger(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
      ).merge

      expect(result).to eq(template)
    end

    it "keeps the destination single-line wrapper once when destination preference applies" do
      template = <<~RUBY
        class Example; def shared; :template; end; end
      RUBY

      dest = <<~RUBY
        class Example; def shared; :destination; end; def custom; :custom; end; end
      RUBY

      result = build_merger(template, dest, preference: :destination).merge

      expect(result).to eq(dest)
    end
  end
end
