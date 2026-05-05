# frozen_string_literal: true

require_relative "../spec_helper"
require "open3"

RSpec.describe "bundle gem scaffold + kettle-jem", :system do
  let(:sandbox_root) { File.expand_path("../../../tmp/sandbox", __dir__) }
  let(:gem_root) { File.join(sandbox_root, "dummy-gem") }
  let(:env) { { "KJ_MIN_DIVERGENCE_THRESHOLD" => "5" } }

  before do
    FileUtils.rm_rf(gem_root)
    FileUtils.mkdir_p(sandbox_root)
    scaffold_bundle_gem!
    normalize_scaffold_gemspec!
  end

  after do
    FileUtils.rm_rf(gem_root)
  end

  def scaffold_bundle_gem!
    stdout, stderr, status = Open3.capture3(
      "bundle",
      "gem",
      "dummy-gem",
      "--no-git",
      "--no-ci",
      "--no-mit",
      "--no-coc",
      "--no-ext",
      "--test=rspec",
      "--no-changelog",
      "--no-linter",
      "--no-github-username",
      chdir: sandbox_root
    )
    expect(status.success?).to be(true), "bundle gem failed\nstdout=#{stdout}\nstderr=#{stderr}"
  end

  def normalize_scaffold_gemspec!
    path = File.join(gem_root, "dummy-gem.gemspec")
    content = File.read(path)
    content = content.sub('spec.authors = ["TODO: Write your name"]', 'spec.authors = ["Test User"]')
    content = content.sub('spec.email = ["TODO: Write your email address"]', 'spec.email = ["test@example.com"]')
    content = content.sub(
      'spec.summary = "TODO: Write a short summary, because RubyGems requires one."',
      'spec.summary = "Dummy gem"'
    )
    content = content.sub(
      'spec.description = "TODO: Write a longer description or delete this line."',
      'spec.description = "Dummy gem for kettle-jem system testing."'
    )
    content = content.sub(
      'spec.homepage = "TODO: Put your gem\'s website or public repo URL here."',
      'spec.homepage = "https://github.com/acme/dummy-gem"'
    )
    content = content.sub(
      'spec.metadata["source_code_uri"] = "TODO: Put your gem\'s public repo URL here."',
      'spec.metadata["source_code_uri"] = "https://github.com/acme/dummy-gem"'
    )
    File.write(path, content)
  end

  def enable_packaged_templates!
    path = File.join(gem_root, ".kettle-jem.yml")
    content = File.read(path)
    content = content.sub('project_emoji: ""', 'project_emoji: "💎"')
    content += <<~YAML

      templates:
        root: packaged
        apply: true
        entries:
          - README.md
          - .github/dependabot.yml
          - Gemfile
          - Rakefile
          - gemfiles/modular/style.gemfile
    YAML
    File.write(path, content)
  end

  def seed_destination_readme!
    File.write(File.join(gem_root, "README.md"), <<~MARKDOWN)
      # 1️⃣ Dummy::Gem

      ## Synopsis

      Destination synopsis from the scaffolded project.

      ## Usage

      Destination usage from the scaffolded project.

      ## Note: Local

      Destination note from the scaffolded project.

      ## Installation

      Old scaffold installation notes.
    MARKDOWN
  end

  def seed_destination_dependabot!
    FileUtils.mkdir_p(File.join(gem_root, ".github"))
    File.write(File.join(gem_root, ".github/dependabot.yml"), <<~YAML)
      updates:
        - package-ecosystem: bundler
          directory: "/"
          schedule:
            interval: daily
    YAML
  end

  it "bootstraps config and applies selected packaged templates to a fresh scaffold" do
    bootstrap = Kettle::Jem.apply_project(gem_root, env: env)
    bootstrap_report = bootstrap.fetch(:recipe_reports).find do |report|
      report.fetch(:recipe_name) == "kettle_config_bootstrap"
    end
    expect(bootstrap_report.fetch(:changed)).to be(true)
    expect(File.read(File.join(gem_root, ".kettle-jem.yml"))).to include("# kettle-jem configuration file")
    expect(File.read(File.join(gem_root, ".kettle-jem.yml"))).to include("min_divergence_threshold: 5")
    expect(bootstrap.fetch(:changed_files)).to include(
      ".github/FUNDING.yml",
      ".github/workflows/ci.yml",
      ".kettle-jem.yml",
      "Rakefile"
    )

    enable_packaged_templates!
    seed_destination_readme!
    seed_destination_dependabot!

    apply = Kettle::Jem.apply_project(gem_root, env: env)
    expect(apply.fetch(:changed_files)).to include(
      ".github/dependabot.yml",
      "Gemfile",
      "Rakefile",
      "README.md",
      "gemfiles/modular/style.gemfile"
    )
    expect(File).to exist(File.join(gem_root, ".github/FUNDING.yml"))
    expect(File).to exist(File.join(gem_root, ".github/workflows/ci.yml"))

    readme = File.read(File.join(gem_root, "README.md"))
    expect(readme).to include("# 💎 Dummy::Gem")
    expect(readme).to include("## 🌻 Synopsis\n\nDestination synopsis from the scaffolded project.")
    expect(readme).to include("## 🔧 Basic Usage\n\nDestination usage from the scaffolded project.")
    expect(readme).not_to include("Old scaffold installation notes.")
    expect(readme).to include("Compatible with MRI Ruby 3.2.0+")
    expect(readme).to include("https://github.com/acme/dummy-gem")

    dependabot = YAML.safe_load(File.read(File.join(gem_root, ".github/dependabot.yml")))
    expect(dependabot).to eq(
      "updates" => [
        {
          "directory" => "/",
          "package-ecosystem" => "bundler",
          "schedule" => { "interval" => "daily" },
        },
      ],
      "version" => 2
    )

    style_gemfile = File.read(File.join(gem_root, "gemfiles/modular/style.gemfile"))
    expect(style_gemfile).to include('gem "rubocop-lts", "~> 24.0"')
    expect(style_gemfile).to include('gem "rubocop-ruby3_2"')

    gemfile = File.read(File.join(gem_root, "Gemfile"))
    expect(gemfile).to include('source "https://gem.coop"')
    expect(gemfile).not_to include('source "https://rubygems.org"')
    expect(gemfile.scan(/^gemspec$/).size).to eq(1)
    expect(gemfile.scan('eval_gemfile "gemfiles/modular/style.gemfile"').size).to eq(1)
    expect(gemfile).to include('gem "irb"')

    rakefile = File.read(File.join(gem_root, "Rakefile"))
    expect(rakefile).to include('require "bundler/gem_tasks"')
    expect(rakefile).to include('require "kettle/dev"')
    expect(rakefile.scan(/^task\s+:default\b/).size).to eq(1)
    expect(rakefile).to include('desc "Default tasks aggregator"')
    expect(rakefile.index('desc "Default tasks aggregator"')).to be < rakefile.index("task :default do")
    expect(rakefile.scan('task("kettle:jem:selftest")').size).to eq(1)
    expect(rakefile.scan('task("build:generate_checksums")').size).to eq(1)

    second_apply = Kettle::Jem.apply_project(gem_root, env: env)
    expect(second_apply.fetch(:changed_files)).not_to include(
      ".github/dependabot.yml",
      "Gemfile"
    )
  end
end
