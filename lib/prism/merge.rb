# frozen_string_literal: true

# External gems
require "prism"
require "version_gem"

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
  # @see FileAligner Identifies matching sections and boundaries
  # @see ConflictResolver Resolves content within boundaries
  module Merge
    # Base error class for Prism::Merge
    class Error < StandardError; end

    # Raised when the template/destination file has parsing errors
    class ParseError < Error
      # @return [String] The content that failed to parse
      attr_reader :content

      # @return [Prism::ParseResult] The Prism parse result containing error details
      attr_reader :parse_result

      # @param message [String] Error message
      # @param content [String] The Ruby source that failed to parse
      # @param parse_result [Prism::ParseResult] Parse result with error information
      def initialize(message, content:, parse_result:)
        super(message)
        @content = content
        @parse_result = parse_result
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
    #     e.parse_result.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
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
    #     e.parse_result.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    autoload :DebugLogger, "prism/merge/debug_logger"
    autoload :FreezeNode, "prism/merge/freeze_node"
    autoload :FileAnalysis, "prism/merge/file_analysis"
    autoload :MergeResult, "prism/merge/merge_result"
    autoload :FileAligner, "prism/merge/file_aligner"
    autoload :ConflictResolver, "prism/merge/conflict_resolver"
    autoload :SmartMerger, "prism/merge/smart_merger"
  end
end

Prism::Merge::Version.class_eval do
  extend VersionGem::Basic
end
