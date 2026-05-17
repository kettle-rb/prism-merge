# frozen_string_literal: true

require_relative "tree_haver/version"

module TreeHaver
  PACKAGE_NAME = "tree_haver"

  class Error < StandardError; end
  class NotAvailable < Error; end
  class BackendConflict < Error; end

  module Backends
    module MRI
      def self.available? = false
    end

    module FFI
      def self.available? = false
    end

    module Rust
      def self.available? = false
    end

    module Java
      def self.available? = false
    end
  end
end

require_relative "tree_haver/backend_registry"
require_relative "tree_haver/backend_context"
require_relative "tree_haver/contracts"
require_relative "tree_haver/base/point"
require_relative "tree_haver/base/language"
require_relative "tree_haver/base/parser"
require_relative "tree_haver/base/tree"
require_relative "tree_haver/base/node"
require_relative "tree_haver/base/comment"
require_relative "tree_haver/language_registry"
require_relative "tree_haver/path_validator"
require_relative "tree_haver/library_path_utils"
require_relative "tree_haver/grammar_finder"
require_relative "tree_haver/citrus_grammar_finder"
require_relative "tree_haver/parslet_grammar_finder"
require_relative "tree_haver/peg_backends"
require_relative "tree_haver/kaitai_backend"
require_relative "tree_haver/language_pack"
require_relative "tree_haver/backends/psych"
require_relative "tree_haver/backends/citrus"
require_relative "tree_haver/backends/parslet"

module TreeHaver
  module_function

  def register_language(name, path: nil, symbol: nil, grammar_module: nil, grammar_class: nil, backend_module: nil, backend_type: nil, gem_name: nil)
    if path
      LanguageRegistry.register(name, :tree_sitter, path: path, symbol: symbol)
    elsif grammar_module
      LanguageRegistry.register(name, :citrus, grammar_module: grammar_module, gem_name: gem_name)
    elsif grammar_class
      LanguageRegistry.register(name, :parslet, grammar_class: grammar_class, gem_name: gem_name)
    elsif backend_module
      LanguageRegistry.register(name, backend_type || backend_module.name.split("::").last.downcase.to_sym, backend_module: backend_module, gem_name: gem_name)
    else
      raise ArgumentError, "Provide path:, grammar_module:, grammar_class:, or backend_module:"
    end
  end

  def registered_languages(name)
    LanguageRegistry.registered(name) || {}
  end

  def parser_for(language_name, library_path: nil, symbol: nil, citrus_config: nil, parslet_config: nil)
    name = language_name.to_sym

    if library_path
      return parser_for_tree_sitter(name, library_path, symbol)
    end

    registrations = LanguageRegistry.registered(name) || {}

    if (config = registrations[:psych])
      return parser_for_backend_module(config.fetch(:backend_module), name)
    end

    if (config = registrations[:citrus]) || citrus_config
      module_config = config || citrus_config
      return parser_for_citrus(module_config.fetch(:grammar_module))
    end

    if (config = registrations[:parslet]) || parslet_config
      class_config = config || parslet_config
      return parser_for_parslet(class_config.fetch(:grammar_class))
    end

    if (config = registrations[:tree_sitter])
      return parser_for_tree_sitter(name, config[:path], config[:symbol])
    end

    raise NotAvailable, "No parser registered for #{name}"
  end

  def parser_for_backend_module(backend_module, name)
    parser = backend_module::Parser.new
    language_factory = backend_module::Language
    parser.language = if language_factory.respond_to?(name)
      language_factory.public_send(name)
    elsif language_factory.respond_to?(:from_library)
      language_factory.from_library(nil, name: name)
    else
      language_factory.new(name)
    end
    parser
  end
  private_class_method :parser_for_backend_module

  def parser_for_citrus(grammar_module)
    parser = Backends::Citrus::Parser.new
    parser.language = Backends::Citrus::Language.new(grammar_module)
    parser
  end
  private_class_method :parser_for_citrus

  def parser_for_parslet(grammar_class)
    parser = Backends::Parslet::Parser.new
    parser.language = Backends::Parslet::Language.new(grammar_class)
    parser
  end
  private_class_method :parser_for_parslet

  def parser_for_tree_sitter(name, library_path, symbol)
    raise NotAvailable, "Tree-sitter parser_for is not available without a registered native TreeHaver backend for #{name}: #{library_path} #{symbol}"
  end
  private_class_method :parser_for_tree_sitter
end
