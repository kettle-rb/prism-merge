# frozen_string_literal: true

require_relative "spec_helper"

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
end
