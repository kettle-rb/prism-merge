# frozen_string_literal: true

gem_version =
  if RUBY_VERSION >= "3.1" # rubocop:disable Gemspec/RubyVersionGlobalsUsage
    # Loading version into an anonymous module allows version.rb to get code coverage from SimpleCov!
    # See: https://github.com/simplecov-ruby/simplecov/issues/557#issuecomment-2630782358
    Module.new.tap { |mod| Kernel.load("lib/kettle/soup/cover/version.rb", mod) }::Kettle::Soup::Cover::Version::VERSION
  else
    # TODO: Remove this hack once support for Ruby 3.0 and below is removed
    Kernel.load("lib/kettle/soup/cover/version.rb")
    g_ver = Kettle::Soup::Cover::Version::VERSION
    Kettle::Soup::Cover::Version.send(:remove_const, :VERSION) # rubocop:disable RSpec/RemoveConst
    g_ver
  end

Gem::Specification.new do |spec|
  spec.name = "kettle-soup-cover"
  spec.version = gem_version
  spec.authors = ["Peter Boling"]
  spec.email = ["floss@galtzo.com"]

  # Linux distros often package gems and securely certify them independent
  #   of the official RubyGem certification process. Allowed via ENV["SKIP_GEM_SIGNING"]
  # Ref: https://gitlab.com/oauth-xx/version_gem/-/issues/3
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

  spec.summary = "🍲 kettle-rb OOTB SimpleCov config supporting every CI platform & coverage tool"
  spec.description = <<~DESC
    🍲 A Covered Kettle of Test Coverage SOUP (Software of Unknown Provenance)
    Four-line SimpleCov config, w/ curated, opinionated, pre-configured, dependencies
    for every CI platform, batteries included.
    Fund overlooked open source projects - bottom of stack, dev/test dependencies: floss-funding.dev
  DESC
  gh_mirror = "https://github.com/kettle-rb/#{spec.name}"
  gl_homepage = "https://gitlab.com/kettle-rb/#{spec.name}"
  spec.homepage = gl_homepage
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata["homepage_uri"] = "https://#{spec.name}.galtzo.com/"
  spec.metadata["source_code_uri"] = "#{gh_mirror}/releases/tag/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{gl_homepage}/-/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{gl_homepage}/-/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["wiki_uri"] = "#{gl_homepage}/-/wiki"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["news_uri"] = "https://www.railsbling.com/tags/#{spec.name}"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files are part of each release.
  spec.files = Dir[
    # Splats (alphabetical)
    "lib/**/*.rb",
    "lib/**/rakelib/*.rake",
    "sig/**/*.rbs",
  ]
  # Automatically included with gem package, no need to list again in files.
  spec.extra_rdoc_files = Dir[
    # Files (alphabetical)
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE.txt",
    "README.md",
    "SECURITY.md",
  ]
  spec.rdoc_options += [
    "--title",
    "#{spec.name} - #{spec.summary}",
    "--main",
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE.txt",
    "README.md",
    "SECURITY.md",
    "--line-numbers",
    "--inline-source",
    "--quiet",
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = []

  # Utilities
  spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.8")

  # Code Coverage
  # CodeCov + GitHub setup is not via gems: https://github.com/marketplace/actions/codecov
  spec.add_dependency("simplecov", "~> 0.22") # Includes dependency on simplecov-html
  spec.add_dependency("simplecov-cobertura", "~> 3.0") # Ruby >= 2.5, provides GitLab, Jenkins compatibility (XML)
  spec.add_dependency("simplecov-console", "~> 0.9", ">= 0.9.3") # TTY / Console output
  spec.add_dependency("simplecov-html", "~> 0.13", ">= 0.13.1") # GHA, Human compatibility! (HTML)
  spec.add_dependency("simplecov_json_formatter", "~> 0.1", ">= 0.1.4") # GHA, Jenkins X, CircleCI, Travis CI, BitBucket, CodeClimate compatibility (JSON)
  spec.add_dependency("simplecov-lcov", "~> 0.8") # GHA, Jenkins X, CircleCI, Travis CI, TeamCity, GCOV compatibility
  spec.add_dependency("simplecov-rcov", "~> 0.3", ">= 0.3.7") # Hudson compatibility

  spec.add_development_dependency("kettle-dev", "~> 1.2")                           # ruby >= 2.3.0
  # ruby >= 2.3.0

  # Release Tasks
  spec.add_development_dependency("rake", "~> 13.0")                                # ruby >= 2.2.0
  # ruby >= 2.2.0
  # Ruby >= 2.3.0
  spec.add_development_dependency("stone_checksums", "~> 1.0", ">= 1.0.3")          # ruby >= 2.2.0
  # ruby >= 2.2.0
  # Ruby >= 2.2.0

  # Documentation
  spec.add_development_dependency("yard", "~> 0.9", ">= 0.9.37")
  spec.add_development_dependency("yard-junk", "~> 0.0", ">= 0.0.10")

  # Linting
  spec.add_development_dependency("rubocop-lts", "~> 18.1", ">= 18.2.1") # Lint & Style Support for Ruby 2.7+
  spec.add_development_dependency("rubocop-packaging", "~> 0.6", ">= 0.6.0")
  spec.add_development_dependency("rubocop-rspec", "~> 3.5")

  # Testing
  spec.add_development_dependency("rspec", "~> 3.13")                               # Ruby >= 0
  spec.add_development_dependency("rspec-block_is_expected", "~> 1.0", ">= 1.0.6")  # Ruby >= 1.8.7
  spec.add_development_dependency("rspec_junit_formatter", "~> 0.6")                # Ruby >= 2.3.0, for GitLab Test Result Parsing
  spec.add_development_dependency("rspec-stubbed_env", "~> 1.0", ">= 1.0.2")        # Ruby >= 1.8.7
  spec.add_development_dependency("silent_stream", "~> 1.0", ">= 1.0.11")           # Ruby >= 2.3.0
end
