# frozen_string_literal: true

RSpec.describe Prism::Merge::RecursiveNodeBodyMerger do
  def merger_for(template, dest, preference: :template, **options)
    merger = Prism::Merge::SmartMerger.new(template, dest, preference: preference, **options)
    merger.instance_variable_set(:@result, merger.send(:build_result))
    merger
  end

  def first_node(merger, side)
    analysis = side == :template ? merger.template_analysis : merger.dest_analysis
    analysis.statements.first
  end

  def recursive_result(template, dest, preference: :template, **options)
    merger = merger_for(template, dest, preference: preference, **options)

    described_class.new(merger: merger).merge(
      template_node: first_node(merger, :template),
      dest_node: first_node(merger, :destination),
    )

    merger.result.to_s
  end

  describe "#merge" do
    it "preserves destination leading comments when the template-preferred wrapper has none" do
      template = <<~RUBY
        class Example
          def shared
            :template
          end
        end
      RUBY

      dest = <<~RUBY
        # Existing documentation
        class Example
          def shared
            :destination
          end

          def custom
            :custom
          end
        end
      RUBY

      result = recursive_result(template, dest, add_template_only_nodes: true)

      expect(result).to include("# Existing documentation")
      expect(result).to include(":template")
      expect(result).to include("def custom")
    end

    it "falls back to destination inline comments for template-preferred opening and closing wrapper lines" do
      template = <<~RUBY
        class Example
          def shared
            :template
          end
        end
      RUBY

      dest = <<~RUBY
        class Example # keep wrapper note
          def shared
            :destination
          end
        end # keep closing note
      RUBY

      result = recursive_result(template, dest)

      expect(result.lines.first.chomp).to eq("class Example # keep wrapper note")
      expect(result.lines.last.chomp).to eq("end # keep closing note")
    end

    it "recursively emits begin wrappers with merged rescue clauses and copied ensure tails" do
      template = <<~RUBY
        begin
        rescue StandardError
          recover
        end
      RUBY

      dest = <<~RUBY
        begin
        rescue StandardError => error
          recover
          audit(error)
        ensure
          cleanup
        end
      RUBY

      result = recursive_result(template, dest)

      expect(result).to eq(<<~RUBY)
        begin
        rescue StandardError => error
          recover
          audit(error)
        ensure
          cleanup
        end
      RUBY
    end

    it "preserves destination-only same-line block statements on the wrapper opening line" do
      template = <<~RUBY
        task do |task_name| shared_call
          destination_fallback_call
        end
      RUBY

      dest = <<~RUBY
        task do |task_name| shared_call; dest_only_call
          destination_fallback_call
        end
      RUBY

      result = recursive_result(template, dest)

      expect(result).to eq(<<~RUBY)
        task do |task_name| shared_call
        dest_only_call
          destination_fallback_call
        end
      RUBY
    end

    it "preserves trailing blank lines at the end of a recursively merged wrapper body" do
      template = <<~RUBY
        class Config
          def updated
            :template
          end


        end
      RUBY

      dest = <<~RUBY
        class Config
          def updated
            :destination
          end



        end
      RUBY

      result = recursive_result(template, dest, preference: :destination)

      expect(result).to eq(dest)
    end

    it "preserves nested line provenance for recursively merged body lines" do
      template = <<~RUBY
        class Config
          def updated
            :template_updated
          end
        end
      RUBY

      dest = <<~RUBY
        class Config
          def updated
            :destination_updated
          end

          def custom
            :destination_custom
          end
        end
      RUBY

      merger = merger_for(template, dest, preference: :template)

      described_class.new(merger: merger).merge(
        template_node: first_node(merger, :template),
        dest_node: first_node(merger, :destination),
      )

      expect(merger.result.line_metadata).to include(
        include(decision: :kept_template, template_line: 2, dest_line: nil),
        include(decision: :kept_template, template_line: 3, dest_line: nil),
        include(decision: :kept_template, template_line: 4, dest_line: nil),
        include(decision: :kept_destination, template_line: nil, dest_line: 6),
        include(decision: :kept_destination, template_line: nil, dest_line: 7),
        include(decision: :kept_destination, template_line: nil, dest_line: 8),
      )
    end

    it "does not duplicate or misorder inline comments owned by opening-line body statements" do
      template = <<~RUBY
        task do |task_name| shared_call
          destination_fallback_call
        end
      RUBY

      dest = <<~RUBY
        task do |task_name| shared_call # keep this
          destination_fallback_call
        end
      RUBY

      result = recursive_result(template, dest, preference: :template)

      expect(result).to eq(<<~RUBY)
        task do |task_name| shared_call # keep this
          destination_fallback_call
        end
      RUBY
      expect(result.scan("# keep this").size).to eq(1)
    end

    it "preserves indentation when destination-only same-line siblings are split inside recursive bodies" do
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

      result = recursive_result(template, dest, preference: :template)

      expect(result).to eq(<<~RUBY)
        class Config
          shared_call
          dest_only_call
        end
      RUBY
    end
  end
end
