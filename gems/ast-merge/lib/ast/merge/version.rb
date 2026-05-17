# frozen_string_literal: true

require "version_gem/basic"

module Ast
  module Merge
    module Version
      VERSION = "7.0.0"
      extend VersionGem::Basic
    end

    VERSION = Version::VERSION
  end
end
