# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "rubygems/package"

RSpec.describe "kettle-jem release packaging" do
  let(:gem_root) { Pathname(__dir__).join("..").expand_path }

  def load_gemspec(gem_root)
    Dir.chdir(gem_root) do
      Gem::Specification.load("kettle-jem.gemspec")
    end
  end

  it "packages runtime template assets used by packaged template application" do
    spec = load_gemspec(gem_root)
    gemspec_source = File.read(gem_root.join("kettle-jem.gemspec"))
    files = spec.files
    expected_template_files = Dir.chdir(gem_root) do
      Dir.glob("lib/kettle/jem/templates/**/*", File::FNM_DOTMATCH).select do |path|
        File.file?(path) && ![".", ".."].include?(File.basename(path))
      end
    end

    expect(gemspec_source).to include("Module.new.tap")
    expect(gemspec_source).to include("spec.metadata[\"news_uri\"]")
    expect(gemspec_source).to include("spec.rdoc_options +=")
    expect(spec.summary).to eq("🍲 Gem templating engine using AST-based merging and configurable token resolution.")
    expect(spec.homepage).to eq("https://github.com/kettle-rb/kettle-jem")
    expect(spec.metadata["homepage_uri"]).to eq("https://kettle-jem.galtzo.com/")
    expect(spec.executables).to eq(["kettle-jem"])
    expect(File.executable?(gem_root.join("exe/kettle-jem"))).to be(true)
    expect(expected_template_files).not_to be_empty
    expect(files).to include(*expected_template_files)
    expect(files).to include("certs/pboling.pem")
    expect(spec.extra_rdoc_files).to include("README.md")
  end

  it "builds an artifact that can run kettle-jem from unpacked package files" do
    tmp_root = gem_root.join("spec/tmp/release-packaging")
    FileUtils.rm_rf(tmp_root)
    FileUtils.mkdir_p(tmp_root)
    gem_path = tmp_root.join("kettle-jem.gem")

    stdout, stderr, status = Open3.capture3(
      {"SKIP_GEM_SIGNING" => "1"},
      Gem.ruby,
      "-S",
      "gem",
      "build",
      "kettle-jem.gemspec",
      "--output",
      gem_path.to_s,
      chdir: gem_root.to_s
    )
    expect(status.success?).to be(true), "gem build failed\nstdout=#{stdout}\nstderr=#{stderr}"

    package = Gem::Package.new(gem_path.to_s)
    package_spec = package.spec
    expected_template = "lib/kettle/jem/templates/.kettle-jem.yml.example"
    expect(package_spec.executables).to include("kettle-jem")
    expect(package_spec.files).to include(expected_template)

    unpack_root = tmp_root.join("unpacked")
    FileUtils.mkdir_p(unpack_root)
    package.extract_files(unpack_root.to_s)
    exe = unpack_root.join("exe/kettle-jem")
    expect(File).to exist(exe)
    expect(File).to exist(unpack_root.join(expected_template))

    run_stdout, run_stderr, run_status = Open3.capture3(
      {"RUBYLIB" => unpack_root.join("lib").to_s},
      Gem.ruby,
      exe.to_s,
      "version"
    )
    expect(run_status.success?).to be(true), "artifact executable failed\nstdout=#{run_stdout}\nstderr=#{run_stderr}"
    expect(run_stdout).to eq("#{Kettle::Jem::Version::VERSION}\n")
  end
end
