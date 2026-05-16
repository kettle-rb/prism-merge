# frozen_string_literal: true

require_relative "lib/kettle/jem/version"

Gem::Specification.new do |spec|
  spec.name = "kettle-jem"
  spec.version = Kettle::Jem::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["info@structuredmerge.org"]

  spec.summary = "RubyGems package templating wrapper for Structured Merge"
  spec.description = "RubyGems-focused recipe-pack wrapper that shapes package facts into ast-merge transport."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.required_ruby_version = ">= 4.0.0"

  # Linux distros often package gems and securely certify them independent
  #   of the official RubyGem certification process. Allowed via ENV["SKIP_GEM_SIGNING"]
  # Ref: https://gitlab.com/ruby-oauth/version_gem/-/issues/3
  # Hence, only enable signing if `SKIP_GEM_SIGNING` is not set in ENV.
  # See CONTRIBUTING.md
  unless ENV.include?("SKIP_GEM_SIGNING")
    user_cert = "certs/#{ENV.fetch("GEM_CERT_USER", ENV["USER"])}.pem"
    cert_file_path = File.join(__dir__, user_cert)
    cert_chain = cert_file_path.split(",")
    cert_chain.select! { |fp| File.exist?(fp) }
    if cert_file_path && cert_chain.any?
      spec.cert_chain = cert_chain
      if $PROGRAM_NAME.end_with?("gem") && ARGV[0] == "build"
        spec.signing_key = File.join(Gem.user_home, ".ssh", "gem-private_key.pem")
      end
    end
  end

  spec.metadata["homepage_uri"] = "https://structuredmerge.org"
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  spec.metadata["rubygems_mfa_required"] = "true"

  enumerate_package_files = lambda do |root|
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
      File.file?(path) && ![".", ".."].include?(File.basename(path))
    end
  end

  spec.files = [
    *Dir["lib/**/*.rb"],
    *Dir["lib/**/*.rake"],
    *Dir["lib/**/*.yml"],
    *enumerate_package_files.call("lib/kettle/jem/templates"),
    *Dir["certs/*.pem"],
  ]
  spec.extra_rdoc_files = Dir["README.md"]

  spec.add_dependency "ast-merge", "= #{Kettle::Jem::VERSION}"
  spec.add_dependency "ruby-merge", "= #{Kettle::Jem::VERSION}"
  spec.add_dependency "token-resolver", "~> 1.0", ">= 1.0.2"
  spec.add_dependency "toml-merge", "= #{Kettle::Jem::VERSION}"
  spec.add_dependency "yaml-merge", "= #{Kettle::Jem::VERSION}"
end
