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
    files = spec.files
    expected_template_files = Dir.chdir(gem_root) do
      Dir.glob("lib/kettle/jem/templates/**/*", File::FNM_DOTMATCH).select do |path|
        File.file?(path) && ![".", ".."].include?(File.basename(path))
      end
    end

    expect(expected_template_files).not_to be_empty
    expect(files).to include(*expected_template_files)
    expect(files).to include("certs/pboling.pem")
    expect(spec.extra_rdoc_files).to include("README.md")
  end
end
