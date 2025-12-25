# frozen_string_literal: true

# External gems
require "prism"
require "version_gem"
require "set"

# Shared merge infrastructure
require "ast/merge"

# This gem
require_relative "merge/version"

# Prism::Merge provides a generic Ruby file smart merge system using Prism AST analysis.
# It intelligently merges template and destination Ruby files by identifying matching
# sections (anchors) and resolving differences (boundaries) using structural signatures.
#
# @example Basic usage
#   template = File.read("template.rb")
#   destination = File.read("destination.rb")
#   merger = Prism::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Prism::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:debug]
#   puts debug_result[:statistics]
module Prism
  # Smart merge system for Ruby files using Prism AST analysis.
  # Provides intelligent merging by understanding Ruby code structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Parses and analyzes Ruby source files
  # @see MergeResult Tracks merged content and decisions
  module Merge
    # Base error class for Prism::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a Ruby file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    # Provides Prism-specific `parse_result` attribute.
    class ParseError < Ast::Merge::ParseError
      # @return [Prism::ParseResult, nil] The Prism parse result containing error details
      attr_reader :parse_result

      # @param message [String, nil] Error message (auto-generated if nil)
      # @param errors [Array] Array of error objects (for base class compatibility)
      # @param content [String, nil] The Ruby source that failed to parse
      # @param parse_result [Prism::ParseResult, nil] Parse result with error information
      def initialize(message = nil, errors: [], content: nil, parse_result: nil)
        @parse_result = parse_result
        # If we have a parse_result, use its errors
        effective_errors = parse_result&.errors || errors
        super(message, errors: effective_errors, content: content)
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    class DestinationParseError < ParseError; end

    autoload :Comment, "prism/merge/comment"
    autoload :DebugLogger, "prism/merge/debug_logger"
    autoload :FreezeNode, "prism/merge/freeze_node"
    autoload :FileAnalysis, "prism/merge/file_analysis"
    autoload :MergeResult, "prism/merge/merge_result"
    autoload :SmartMerger, "prism/merge/smart_merger"
    autoload :MethodMatchRefiner, "prism/merge/method_match_refiner"
  end
end

Prism::Merge::Version.class_eval do
  extend VersionGem::Basic
end
