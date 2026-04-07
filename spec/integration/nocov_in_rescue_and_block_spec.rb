# frozen_string_literal: true

require "spec_helper"

# Regression specs for false "unclosed :nocov:" warnings and output corruption when
# a destination file wraps rescue-clause or block bodies in `# :nocov:` pairs but
# the template does not.
#
# Repro: kettle-jem templating of turbo_tests2/Rakefile produced duplicated rescue
# bodies, misplaced `# :nocov:` markers, and stray `end` keywords.
#
# Fixture files are exact copies:
#   destination.rb — turbo_tests2/Rakefile at the known-good commit (86ed8a0)
#   template.rb    — kettle-jem/template/Rakefile.example with {KJ|...} tokens
#                    substituted to match the turbo_tests2 destination
RSpec.describe "nocov wrapper preservation in rescue and block bodies" do
  FIXTURE_DIR = "spec/support/fixtures/rakefile_nocov"

  let(:template_content) { File.read("#{FIXTURE_DIR}/template.rb") }
  let(:dest_content)     { File.read("#{FIXTURE_DIR}/destination.rb") }

  def merge(template, dest, **opts)
    Prism::Merge::SmartMerger.new(
      template, dest,
      preference: :destination,
      add_template_only_nodes: true,
      remove_template_missing_nodes: false,
      freeze_token: "kettle-jem",
      **opts,
    ).merge
  end

  # -------------------------------------------------------------------------
  # Scenario 1: rescue LoadError – dest has :nocov: wrapper, template does not
  # -------------------------------------------------------------------------
  describe "rescue clause where destination wraps body in :nocov:" do
    let(:template) do
      <<~RUBY
        begin
          require "kettle/jem"
        rescue LoadError
          desc("(stub) kettle:jem:selftest is unavailable")
          task("kettle:jem:selftest") do
            warn("NOTE: not installed")
          end
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        begin
          require "kettle/jem"
        rescue LoadError
          # :nocov:
          desc("(stub) kettle:jem:selftest is unavailable")
          task("kettle:jem:selftest") do
            warn("NOTE: not installed")
          end
          # :nocov:
        end
      RUBY
    end

    it "preserves the :nocov: wrapper without corruption" do
      result = merge(template, dest)
      expect(result).to eq(dest)
    end

    it "does not duplicate the rescue body" do
      result = merge(template, dest)
      expect(result.scan("desc(").size).to eq(1)
      expect(result.scan("task(").size).to eq(1)
    end

    it "does not emit stray end keywords" do
      result = merge(template, dest)
      # dest has exactly 2 bare `end` lines: task-block close + begin/rescue close
      expect(result.lines.map(&:strip).count { |l| l == "end" }).to eq(2)
    end

    it "does not emit warnings about unclosed :nocov:" do
      expect { merge(template, dest) }.not_to output(/unclosed.*nocov/i).to_stderr
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 2: block node – dest wraps body in :nocov:, template does not
  # -------------------------------------------------------------------------
  describe "task block where destination wraps body in :nocov:" do
    let(:template) do
      <<~RUBY
        task :default do
          puts "Default task complete."
        end
      RUBY
    end

    let(:dest) do
      <<~RUBY
        task :default do
          # :nocov:
          puts "Default task complete."
          # :nocov:
        end
      RUBY
    end

    it "preserves the :nocov: wrapper without corruption" do
      result = merge(template, dest)
      expect(result).to eq(dest)
    end

    it "does not duplicate puts" do
      result = merge(template, dest)
      expect(result.scan("puts").size).to eq(1)
    end

    it "does not emit warnings about unclosed :nocov:" do
      expect { merge(template, dest) }.not_to output(/unclosed.*nocov/i).to_stderr
    end
  end

  # -------------------------------------------------------------------------
  # Scenario 3: full Rakefile fixture – the exact files that caused the bug
  # -------------------------------------------------------------------------
  describe "full turbo_tests2 Rakefile fixture" do
    it "produces output identical to destination (all :nocov: wrappers preserved)" do
      result = merge(template_content, dest_content)
      expect(result).to eq(dest_content)
    end

    it "has exactly 8 :nocov: markers (4 pairs)" do
      result = merge(template_content, dest_content)
      expect(result.scan("# :nocov:").size).to eq(8)
    end

    it "does not duplicate any rescue body content" do
      result = merge(template_content, dest_content)
      expect(result.scan("desc(\"(stub) kettle:jem:selftest").size).to eq(1)
      expect(result.scan("desc(\"(stub) build:generate_checksums").size).to eq(1)
    end

    it "does not emit any warnings about unclosed :nocov:" do
      expect { merge(template_content, dest_content) }.not_to output(/unclosed.*nocov/i).to_stderr
    end
  end
end
