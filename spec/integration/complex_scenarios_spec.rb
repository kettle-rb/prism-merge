# frozen_string_literal: true

require "spec_helper"

# Tests for complex real-world merge scenarios
RSpec.describe "Complex Real-World Merge Scenarios" do
  describe "gemspec file merge" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          spec.version = "2.0.0"
          spec.authors = ["Template Author"]
          spec.summary = "Updated summary"

          spec.files = Dir["lib/**/*"]
          spec.require_paths = ["lib"]

          spec.add_dependency "rake", "~> 13.0"
          spec.add_development_dependency "rspec", "~> 3.12"
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          spec.version = "1.5.0"
          spec.authors = ["Custom Author", "Another Author"]
          spec.summary = "Custom summary"
          spec.description = "Custom description"

          spec.files = Dir["lib/**/*", "README.md"]
          spec.require_paths = ["lib"]

          spec.add_dependency "rake", "~> 13.0"
          spec.add_dependency "custom_gem", "~> 2.0"
          spec.add_development_dependency "rspec", "~> 3.12"
        end
      RUBY
    end

    it "merges gemspec preserving custom fields" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("my-gem")
      expect(result).to include("Custom Author")
      expect(result).to include("custom_gem")
    end
  end

  describe "Rakefile merge with custom tasks" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        require "bundler/gem_tasks"
        require "rspec/core/rake_task"

        RSpec::Core::RakeTask.new(:spec)

        task default: :spec
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        require "bundler/gem_tasks"
        require "rspec/core/rake_task"

        RSpec::Core::RakeTask.new(:spec)

        desc "Custom task"
        task :custom do
          puts "Running custom task"
        end

        task default: %i[spec custom]
      RUBY
    end

    it "merges Rakefile preserving custom tasks" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("require \"bundler/gem_tasks\"")
      expect(result).to include("Custom task")
      expect(result).to include("task :custom")
    end
  end

  describe "configuration class merge" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        module MyGem
          class Configuration
            attr_accessor :api_key, :timeout, :retries

            def initialize
              @api_key = nil
              @timeout = 30
              @retries = 3
            end

            def validate!
              raise "API key required" unless api_key
            end
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        module MyGem
          class Configuration
            attr_accessor :api_key, :timeout, :retries, :custom_option

            def initialize
              @api_key = nil
              @timeout = 60
              @retries = 5
              @custom_option = "custom"
            end

            def validate!
              raise "API key required" unless api_key
              raise "Custom validation" if custom_option.nil?
            end

            def custom_method
              "custom"
            end
          end
        end
      RUBY
    end

    it "merges configuration class preserving customizations" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("custom_option")
      expect(result).to include("custom_method")
      expect(result).to include("Custom validation")
    end
  end

  describe "test file merge" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        require "spec_helper"

        RSpec.describe MyGem do
          describe "#method_a" do
            it "works" do
              expect(MyGem.method_a).to eq("a")
            end
          end

          describe "#method_b" do
            it "works" do
              expect(MyGem.method_b).to eq("b")
            end
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        require "spec_helper"

        RSpec.describe MyGem do
          describe "#method_a" do
            it "works" do
              expect(MyGem.method_a).to eq("a")
            end

            it "handles edge cases" do
              expect(MyGem.method_a(nil)).to be_nil
            end
          end

          describe "#method_b" do
            it "works" do
              expect(MyGem.method_b).to eq("b")
            end
          end

          describe "#custom_method" do
            it "does custom stuff" do
              expect(MyGem.custom_method).to eq("custom")
            end
          end
        end
      RUBY
    end

    it "merges test files preserving custom test cases" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("method_a")
      expect(result).to include("method_b")
      expect(result).to include("handles edge cases")
      expect(result).to include("custom_method")
    end
  end

  describe "module with mixed content" do
    let(:template_code) do
      <<~RUBY
        # frozen_string_literal: true

        module MyGem
          VERSION = "2.0.0"

          class Error < StandardError; end
          class ValidationError < Error; end

          def self.configure
            yield configuration
          end

          def self.configuration
            @configuration ||= Configuration.new
          end
        end
      RUBY
    end

    let(:dest_code) do
      <<~RUBY
        # frozen_string_literal: true

        module MyGem
          VERSION = "1.5.0"

          class Error < StandardError; end
          class ValidationError < Error; end
          class CustomError < Error; end

          def self.configure
            yield configuration
          end

          def self.configuration
            @configuration ||= Configuration.new
          end

          def self.reset_configuration
            @configuration = nil
          end
        end
      RUBY
    end

    it "merges module with mixed classes and methods" do
      merger = Prism::Merge::SmartMerger.new(
        template_code,
        dest_code,
        signature_match_preference: :destination,
      )
      result = merger.merge

      expect(result).to include("ValidationError")
      expect(result).to include("CustomError")
      expect(result).to include("reset_configuration")
    end
  end
end
