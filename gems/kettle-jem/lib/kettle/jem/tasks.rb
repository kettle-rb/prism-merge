# frozen_string_literal: true

require "rake"

rakelib = File.expand_path("rakelib", __dir__)
Dir[File.join(rakelib, "*.rake")].sort.each { |path| load path }
