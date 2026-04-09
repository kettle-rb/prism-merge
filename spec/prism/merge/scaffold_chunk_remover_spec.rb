# frozen_string_literal: true

require "spec_helper"

RSpec.describe Prism::Merge::ScaffoldChunkRemover do
  let(:full_scaffold) do
    <<~RUBY
      # frozen_string_literal: true

      require "bundler/gem_tasks"
      require "rspec/core/rake_task"

      RSpec::Core::RakeTask.new(:spec)

      require "rubocop/rake_task"

      RuboCop::RakeTask.new

      task default: %i[spec rubocop]
    RUBY
  end

  describe ".remove" do
    context "Group A — bare bundler require" do
      let(:source) do
        <<~RUBY
          # frozen_string_literal: true

          require "bundler/gem_tasks"

          task :build do
            puts "building"
          end
        RUBY
      end

      it "removes the bare require" do
        result = described_class.remove(source, [described_class::BUNDLER_GEM_TASKS_SPEC])
        expect(result).not_to include('require "bundler/gem_tasks"')
        expect(result).to include("task :build")
      end

      context "when guarded with if defined?(Bundler)" do
        let(:source) do
          <<~RUBY
            # frozen_string_literal: true

            if defined?(Bundler)
              require "bundler/gem_tasks"
            end
          RUBY
        end

        it "does NOT remove the guarded require" do
          result = described_class.remove(source, [described_class::BUNDLER_GEM_TASKS_SPEC])
          expect(result).to include('require "bundler/gem_tasks"')
        end
      end
    end

    context "Group B — rspec setup" do
      let(:source) do
        <<~RUBY
          # frozen_string_literal: true

          require "rspec/core/rake_task"

          RSpec::Core::RakeTask.new(:spec)

          task :build do
            puts "building"
          end
        RUBY
      end

      it "removes both anchor and satellite" do
        result = described_class.remove(source, [described_class::RSPEC_SPEC])
        expect(result).not_to include('require "rspec/core/rake_task"')
        expect(result).not_to include("RSpec::Core::RakeTask.new")
        expect(result).to include("task :build")
      end

      context "when anchor and satellite are separated by other nodes" do
        let(:source) do
          <<~RUBY
            # frozen_string_literal: true

            require "rspec/core/rake_task"

            task :build do
              puts "building"
            end

            RSpec::Core::RakeTask.new(:spec)
          RUBY
        end

        it "removes both even when separated" do
          result = described_class.remove(source, [described_class::RSPEC_SPEC])
          expect(result).not_to include('require "rspec/core/rake_task"')
          expect(result).not_to include("RSpec::Core::RakeTask.new")
          expect(result).to include("task :build")
        end
      end
    end

    context "Group C — rubocop setup" do
      let(:source) do
        <<~RUBY
          # frozen_string_literal: true

          require "rubocop/rake_task"

          RuboCop::RakeTask.new

          task :build do
            puts "building"
          end
        RUBY
      end

      it "removes both anchor and satellite" do
        result = described_class.remove(source, [described_class::RUBOCOP_SPEC])
        expect(result).not_to include('require "rubocop/rake_task"')
        expect(result).not_to include("RuboCop::RakeTask.new")
        expect(result).to include("task :build")
      end
    end

    context "Group D — scaffold default task" do
      let(:source) do
        <<~RUBY
          # frozen_string_literal: true

          task default: %i[spec rubocop]

          task :build do
            puts "building"
          end
        RUBY
      end

      it "removes the default task" do
        result = described_class.remove(source, [described_class::DEFAULT_TASK_SPEC])
        expect(result).not_to include("task default:")
        expect(result).to include("task :build")
      end
    end

    context "ALL_SPECS — full scaffold Rakefile" do
      it "removes all scaffold chunks leaving only the frozen magic comment" do
        result = described_class.remove(full_scaffold)
        expect(result.strip).to eq("# frozen_string_literal: true")
      end
    end

    context "idempotency" do
      it "running twice on already-clean source returns the same output" do
        clean = <<~RUBY
          # frozen_string_literal: true

          task :build do
            puts "building"
          end
        RUBY

        first_pass = described_class.remove(clean)
        second_pass = described_class.remove(first_pass)
        expect(second_pass).to eq(first_pass)
      end
    end

    context "safety" do
      it "does NOT remove user-added custom tasks" do
        source = <<~RUBY
          # frozen_string_literal: true

          task :build do
            puts "building"
          end

          task test: [:spec] do
            puts "testing"
          end
        RUBY

        result = described_class.remove(source)
        expect(result).to include("task :build")
        expect(result).to include("task test:")
      end
    end

    context "satellite separation" do
      it "removes require at top and RakeTask.new several nodes below" do
        source = <<~RUBY
          # frozen_string_literal: true

          require "rspec/core/rake_task"

          desc "Custom task one"
          task :custom_one do
            puts "one"
          end

          desc "Custom task two"
          task :custom_two do
            puts "two"
          end

          RSpec::Core::RakeTask.new(:spec)
        RUBY

        result = described_class.remove(source, [described_class::RSPEC_SPEC])
        expect(result).not_to include('require "rspec/core/rake_task"')
        expect(result).not_to include("RSpec::Core::RakeTask.new")
        expect(result).to include("task :custom_one")
        expect(result).to include("task :custom_two")
      end
    end
  end
end
