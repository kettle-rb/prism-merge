# frozen_string_literal: true

RSpec.describe Prism::Merge::CommentOnlyFileMerger do
  def merger_for(template, dest, preference: :template, add_template_only_nodes: false, **options)
    Prism::Merge::SmartMerger.new(
      template,
      dest,
      preference: preference,
      add_template_only_nodes: add_template_only_nodes,
      **options,
    )
  end

  describe "#comment_only_file?" do
    it "recognizes files composed only of comment parser nodes" do
      merger = merger_for("# comment\n", "# other\n")
      comment_only_merger = described_class.new(merger: merger)

      expect(comment_only_merger.comment_only_file?(merger.template_analysis)).to be(true)
    end
  end

  describe "#merge" do
    it "preserves destination shebang and magic prefix without duplicating template magic comments" do
      template = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        # Template comment
      RUBY

      dest = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: false

        # Destination comment
      RUBY

      merger = merger_for(template, dest, preference: :template)
      result = described_class.new(merger: merger).merge.to_s

      expect(result).to start_with("#!/usr/bin/env ruby\n# frozen_string_literal: false\n\n")
      expect(result.scan("frozen_string_literal").size).to eq(1)
    end

    it "retains template-only magic comments when template preference is selected" do
      template = <<~RUBY
        # frozen_string_literal: true

        # Template note
      RUBY

      dest = <<~RUBY
        # Destination note
      RUBY

      merger = merger_for(template, dest, preference: :template)
      result = described_class.new(merger: merger).merge.to_s

      expect(result).to start_with("# frozen_string_literal: true\n")
    end

    it "matches duplicate comment content once and preserves unmatched destination duplicates with destination preference" do
      template = <<~RUBY
        # Shared
      RUBY

      dest = <<~RUBY
        # Shared
        # Shared
      RUBY

      merger = merger_for(template, dest, preference: :destination)
      result = described_class.new(merger: merger).merge.to_s

      expect(result.scan("# Shared").size).to eq(2)
    end

    it "adds template-only comment nodes when requested" do
      template = <<~RUBY
        # Template only
      RUBY

      dest = <<~RUBY
        # Destination only
      RUBY

      merger = merger_for(template, dest, preference: :template, add_template_only_nodes: true)
      result = described_class.new(merger: merger).merge.to_s

      expect(result).to include("# Template only")
    end
  end

  describe "private node output fallbacks" do
    ContentOnlyNode = Struct.new(:content, :line_number)

    class ToStringOnlyNode
      attr_reader :line_number

      def initialize(text, line_number = nil)
        @text = text
        @line_number = line_number
      end

      def to_s
        @text
      end
    end

    it "uses #content for single-line template nodes when #text is unavailable" do
      merger = merger_for("# one\n", "# one\n")
      comment_only_merger = described_class.new(merger: merger)
      merger.instance_variable_set(:@result, merger.send(:build_result))

      comment_only_merger.send(:add_comment_node_to_result, ContentOnlyNode.new("# content fallback", 7), :template)

      expect(merger.result.to_s).to eq("# content fallback\n")
      expect(merger.result.line_metadata.first[:template_line]).to eq(7)
    end

    it "falls back to #to_s when neither #text nor #content is available" do
      merger = merger_for("# one\n", "# one\n")
      comment_only_merger = described_class.new(merger: merger)
      merger.instance_variable_set(:@result, merger.send(:build_result))

      comment_only_merger.send(:add_comment_node_to_result, ToStringOnlyNode.new("# to_s fallback", 8), :destination)

      expect(merger.result.to_s).to eq("# to_s fallback\n")
      expect(merger.result.line_metadata.first[:dest_line]).to eq(8)
    end
  end
end
