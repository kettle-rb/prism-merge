# frozen_string_literal: true

require_relative "../spec_helper"
require "open3"

RSpec.describe "bundle gem scaffold + kettle-jem", :system do
  let(:tmp_root) { File.expand_path("../../tmp/system", __dir__) }
  let(:sandbox_root) { File.join(tmp_root, "bundle-gem-system") }
  let(:gem_root) { File.join(sandbox_root, "dummy-gem") }
  let(:env) { { "KJ_MIN_DIVERGENCE_THRESHOLD" => "5" } }

  before do
    FileUtils.rm_rf(sandbox_root)
    FileUtils.mkdir_p(sandbox_root)
    scaffold_bundle_gem!
    normalize_scaffold_gemspec!
  end

  after do
    FileUtils.rm_rf(sandbox_root)
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
          - gemfiles/modular/style.gemfile
    YAML
    File.write(path, content)
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

    apply = Kettle::Jem.apply_project(gem_root, env: env)
    expect(apply.fetch(:changed_files)).to include(
      "README.md",
      "gemfiles/modular/style.gemfile"
    )
    expect(File).to exist(File.join(gem_root, ".github/FUNDING.yml"))
    expect(File).to exist(File.join(gem_root, ".github/workflows/ci.yml"))

    readme = File.read(File.join(gem_root, "README.md"))
    expect(readme).to include("# 💎 Dummy::Gem")
    expect(readme).to include("Compatible with MRI Ruby 3.2.0+")
    expect(readme).to include("https://github.com/acme/dummy-gem")

    style_gemfile = File.read(File.join(gem_root, "gemfiles/modular/style.gemfile"))
    expect(style_gemfile).to include('gem "rubocop-lts", "~> 24.0"')
    expect(style_gemfile).to include('gem "rubocop-ruby3_2"')

    expect(File.read(File.join(gem_root, "Rakefile"))).not_to include("bundler/gem_tasks")
  end
end
