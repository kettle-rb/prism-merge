# frozen_string_literal: true

require "prism"

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
  module Merge
    # Base error class for Prism::Merge
    class Error < StandardError; end
    
    # Raised when the template/destination file has parsing errors
    class ParseError < Error
      attr_reader :content, :parse_result
      
      def initialize(message, content:, parse_result:)
        super(message)
        @content = content
        @parse_result = parse_result
      end
    end

    class TemplateParseError < ParseError; end
    class DestinationParseError < ParseError; end

    autoload :FileAnalysis, "prism/merge/file_analysis"
    autoload :MergeResult, "prism/merge/merge_result"
    autoload :FileAligner, "prism/merge/file_aligner"
    autoload :ConflictResolver, "prism/merge/conflict_resolver"
    autoload :SmartMerger, "prism/merge/smart_merger"
  end
end
