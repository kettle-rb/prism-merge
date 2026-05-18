# frozen_string_literal: true

RSpec.describe "active Ruby gem version_gem pattern" do
  ruby_gems_root = Pathname(__dir__).join("..", "..").expand_path

  Dir.glob(ruby_gems_root.join("*", "*.gemspec")).sort.each do |gemspec_path|
    gem_root = Pathname(gemspec_path).dirname
    gem_name = File.basename(gemspec_path, ".gemspec")

    it "keeps #{gem_name} aligned with the Kettle/Jem version_gem bootstrap shape" do
      version_paths = Dir.glob(gem_root.join("lib", "**", "version.rb"))
      expect(version_paths).not_to be_empty

      version_paths.each do |version_path|
        version_content = File.read(version_path)
        expect(version_content).to include("module Version")
        expect(version_content).to include("VERSION = Version::VERSION # Traditional Constant Location")
        expect(version_content).not_to include("version_gem")
        expect(version_content).not_to include("VersionGem")

        namespace = version_content.scan(/^\s*module\s+([A-Z][A-Za-z0-9_]*)\s*$/).flatten.take_while { |name| name != "Version" }.join("::")
        expect(namespace).not_to be_empty

        version_dir = File.dirname(version_path)
        entrypoint_path = File.join(File.dirname(version_dir), "#{File.basename(version_dir)}.rb")
        expect(File).to exist(entrypoint_path)

        entrypoint_content = File.read(entrypoint_path)
        version_require = %(require_relative "#{File.basename(version_dir)}/version")
        class_eval = "#{namespace}::Version.class_eval do"
        expect(entrypoint_content).to include('require "version_gem"')
        expect(entrypoint_content).to include(version_require)
        expect(entrypoint_content.index(version_require)).to be < entrypoint_content.index(class_eval)
        expect(entrypoint_content).to include(class_eval)
        expect(entrypoint_content).to include("extend VersionGem::Basic")
      end

      expect(File.read(gemspec_path)).to match(/spec\.add_dependency(?:\(| )["']version_gem["']/)
    end
  end
end
