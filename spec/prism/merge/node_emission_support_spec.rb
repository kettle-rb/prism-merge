# frozen_string_literal: true

RSpec.describe Prism::Merge::NodeEmissionSupport do
  def merger_for(template, dest, preference: :template, **options)
    Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
  end

  def first_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def second_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements[1]
  end

  describe "#emit_dest_prefix_lines" do
    it "emits shebang, destination magic comment, and separating blank line before the first node" do
      source = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        # docs
        class Example
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emitted_line = support.emit_dest_prefix_lines(result: result, analysis: merger.dest_analysis)

      expect(emitted_line).to eq(3)
      expect(result.to_s).to eq("#!/usr/bin/env ruby\n# frozen_string_literal: true\n\n")
      expect(merger.instance_variable_get(:@dest_prefix_comment_lines)).to eq(Set[1, 2, 3])
    end
  end

  describe "#emit_dest_gap_lines" do
    it "emits only blank lines between destination nodes" do
      source = <<~RUBY
        class A
        end


        class B
        end
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      last_output_line = support.emit_dest_gap_lines(
        result: result,
        analysis: merger.dest_analysis,
        last_output_line: 2,
        next_node: second_node(merger, :destination),
      )

      expect(last_output_line).to eq(2)
      expect(result.to_s).to eq("\n\n")
      expect(result.line_metadata.map { |meta| meta[:dest_line] }).to eq([3, 4])
    end
  end

  describe "#emit_matched_template_node" do
    it "falls back to destination leading, inline, and external trailing comments while keeping template code" do
      template = <<~RUBY
        def example
          :template
        end
      RUBY

      dest = <<~RUBY
        # User docs
        def example
          :destination
        end # keep end note

        # trailing note
      RUBY

      merger = merger_for(template, dest, preference: :template)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      emission = support.emit_matched_template_node(
        result: result,
        template_node: first_node(merger, :template),
        dest_node: first_node(merger, :destination),
      )

      expect(emission).to eq({last_emitted_dest_line: 6})
      expect(result.to_s).to eq(<<~RUBY)
        # User docs
        def example
          :template
        end # keep end note

        # trailing note
      RUBY
      expect(result.line_metadata.map { |meta| [meta[:template_line], meta[:dest_line]] }).to eq([
        [nil, 1],
        [1, nil],
        [2, nil],
        [3, nil],
        [nil, 5],
        [nil, 6],
      ])
    end
  end

  describe "#emit_node" do
    it "emits node source and trailing separator blank line with template provenance" do
      source = <<~RUBY
        def example
          :body
        end

        EXTRA = true
      RUBY

      merger = merger_for(source, source)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: first_node(merger, :template),
        analysis: merger.template_analysis,
        source: :template,
      )

      expect(result.to_s).to eq("def example\n  :body\nend\n\n")
      expect(result.line_metadata.map { |meta| meta[:template_line] }).to eq([1, 2, 3, 4])
    end

    it "re-attaches owned inline comments for partial same-line destination nodes" do
      template = <<~RUBY
        shared_call
      RUBY

      dest = <<~RUBY
        shared_call; dest_only_call # keep this
      RUBY

      merger = merger_for(template, dest)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)

      support.emit_node(
        result: result,
        node: second_node(merger, :destination),
        analysis: merger.dest_analysis,
        source: :destination,
      )

      expect(result.to_s).to eq("dest_only_call # keep this\n")
      expect(result.line_metadata.first[:dest_line]).to eq(1)
    end

    it "preserves indentation for partial same-line destination nodes split out of an indented scope" do
      template = <<~RUBY
        class Config
          shared_call
        end
      RUBY

      dest = <<~RUBY
        class Config
          shared_call; dest_only_call
        end
      RUBY

      merger = merger_for(template, dest)
      support = described_class.new(merger: merger)
      result = merger.send(:build_result)
      nested_dest_node = merger.dest_analysis.statements.first.body.body[1]

      support.emit_node(
        result: result,
        node: nested_dest_node,
        analysis: merger.dest_analysis,
        source: :destination,
      )

      expect(result.to_s).to eq("  dest_only_call\n")
      expect(result.line_metadata.first[:dest_line]).to eq(2)
    end
  end
end
