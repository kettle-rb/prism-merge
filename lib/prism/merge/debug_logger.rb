# frozen_string_literal: true

module Prism
  module Merge
    # Internal debug logging utility.
    # Only logs when PRISM_MERGE_DEBUG environment variable is set.
    # Optionally uses Ruby's Logger if available, otherwise falls back to simple puts.
    # rubocop:disable ThreadSafety/ClassInstanceVariable
    module DebugLogger
      @logger = nil
      # :nocov:
      @enabled = ENV.fetch("PRISM_MERGE_DEBUG", "false").casecmp?("true")
      # :nocov:

      class << self
        attr_reader :enabled

        # Log a debug message if debugging is enabled
        # @param message [String] The message to log
        # @param context [Hash] Optional context information
        def debug(message, context = {})
          return unless enabled

          if logger_available?
            ensure_logger
            context_str = context.empty? ? "" : " #{context.inspect}"
            @logger.debug("[prism-merge] #{message}#{context_str}")
          else
            context_str = context.empty? ? "" : " | #{context.inspect}"
            puts "[DEBUG][prism-merge] #{message}#{context_str}"
          end
        end

        private

        # Check if Logger is available without raising an error
        def logger_available?
          defined?(Logger)
        end

        # Initialize logger if not already done
        def ensure_logger
          return if @logger

          require "logger"
          @logger = Logger.new($stdout)
          @logger.level = Logger::DEBUG
        rescue LoadError
          # Logger not available, will fall back to puts
          nil
        end
      end
    end
    # rubocop:enable ThreadSafety/ClassInstanceVariable
  end
end
