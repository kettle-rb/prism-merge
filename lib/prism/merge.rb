# frozen_string_literal: true

# External gems
require "prism"
require "version_gem"
require "set"

# Shared merge infrastructure
require "ast/merge"

# Unified AST abstraction layer — all parser calls route through TreeHaver
require "tree_haver"

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
    autoload :BeginNodeClauseBodySupport, "prism/merge/begin_node_clause_body_support"
    autoload :BeginNodeClauseBodyMerger, "prism/merge/begin_node_clause_body_merger"
    autoload :BeginNodeClauseHeaderEmitter, "prism/merge/begin_node_clause_header_emitter"
    autoload :BeginNodeMergePlanner, "prism/merge/begin_node_merge_planner"
    autoload :BeginNodePlanEmitter, "prism/merge/begin_node_plan_emitter"
    autoload :BeginNodeStructure, "prism/merge/begin_node_structure"
    autoload :BeginNodeRescueSemantics, "prism/merge/begin_node_rescue_semantics"
    autoload :RecursiveNodeBodyMerger, "prism/merge/recursive_node_body_merger"
    autoload :RecursiveMergePolicy, "prism/merge/recursive_merge_policy"
    autoload :TopLevelMergeRunner, "prism/merge/top_level_merge_runner"
    autoload :WrapperCommentSupport, "prism/merge/wrapper_comment_support"

    # Base error class for Prism::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when corruption handling is configured to fail instead of heal.
    class CorruptionDetectedError < Error; end

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

    # Raised when a merge path expects a concrete source line from analysis, but
    # the provided analysis object cannot supply it.
    class MissingAnalyzedLineError < Error; end

    autoload :BlockDirectiveDetector, "prism/merge/block_directive_detector"
    autoload :Comment, "prism/merge/comment"
    autoload :CommentOnlyFileMerger, "prism/merge/comment_only_file_merger"
    autoload :DebugLogger, "prism/merge/debug_logger"
    autoload :GemspecVarRenamer, "prism/merge/gemspec_var_renamer"
    autoload :MagicCommentSupport, "prism/merge/magic_comment_support"
    autoload :NodeEmissionSupport, "prism/merge/node_emission_support"
    autoload :NodeBodyLayout, "prism/merge/node_body_layout"
    autoload :NodeTypeNormalizer, "prism/merge/node_type_normalizer"
    autoload :NodeWrapper, "prism/merge/node_wrapper"
    autoload :FreezeNode, "prism/merge/freeze_node"
    autoload :FileAnalysis, "prism/merge/file_analysis"
    autoload :MergeResult, "prism/merge/merge_result"
    autoload :MethodMatchRefiner, "prism/merge/method_match_refiner"
    autoload :NestedStatementWalker, "prism/merge/nested_statement_walker"
    autoload :NocovNode, "prism/merge/nocov_node"
    autoload :NoCovWrapper, "prism/merge/nocov_wrapper"
    autoload :PartialTemplateMerger, "prism/merge/partial_template_merger"
    autoload :PartialTemplateNode, "prism/merge/partial_template_node"
    autoload :ScaffoldChunkRemover, "prism/merge/scaffold_chunk_remover"
    autoload :SmartMerger, "prism/merge/smart_merger"
    autoload :SourceLineLookup, "prism/merge/source_line_lookup"
  end
end

Prism::Merge::Version.class_eval do
  extend VersionGem::Basic
end
