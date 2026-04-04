# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "example-gem"
  spec.version = "1.0.0"

  spec.post_install_message = <<~MESSAGE
    This gem is now a compatibility shim.

    New projects should prefer:
      gem "other-gem"
  MESSAGE

  spec.add_dependency("other-gem", ">= 2.0")
  spec.add_dependency("version_gem", ">= 1.0")
end
