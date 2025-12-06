# frozen_string_literal: true

module Prism
  module Merge
    # Debug logging utility for Prism::Merge.
    # Provides conditional debug output based on environment configuration.
    #
    # @example Enable debug logging
    #   ENV['PRISM_MERGE_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "mapping", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      # Benchmark is optional - gracefully degrade if not available
      BENCHMARK_AVAILABLE = begin
        require "benchmark"
        true
      rescue LoadError
        false
      end

      # Check if debug mode is enabled
      #
      # @return [Boolean]
      def self.enabled?
        ENV["PRISM_MERGE_DEBUG"] == "1" || ENV["PRISM_MERGE_DEBUG"] == "true"
      end

      # Log a debug message with optional context
      #
      # @param message [String] The debug message
      # @param context [Hash] Optional context to include
      def self.debug(message, context = {})
        return unless enabled?

        output = "[Prism::Merge] #{message}"
        output += " #{context.inspect}" unless context.empty?
        warn output
      end

      # Log an info message (always shown when debug is enabled)
      #
      # @param message [String] The info message
      def self.info(message)
        return unless enabled?

        warn "[Prism::Merge INFO] #{message}"
      end

      # Log a warning message (always shown)
      #
      # @param message [String] The warning message
      def self.warning(message)
        warn "[Prism::Merge WARNING] #{message}"
      end

      # Time a block and log the duration
      #
      # @param operation [String] Name of the operation
      # @yield The block to time
      # @return [Object] The result of the block
      def self.time(operation)
        unless enabled?
          return yield
        end

        unless BENCHMARK_AVAILABLE
          warning("Benchmark gem not available - timing disabled for: #{operation}")
          return yield
        end

        debug("Starting: #{operation}")
        result = nil
        timing = Benchmark.measure { result = yield }
        debug("Completed: #{operation}", {
          real_ms: (timing.real * 1000).round(2),
          user_ms: (timing.utime * 1000).round(2),
          system_ms: (timing.stime * 1000).round(2),
        })
        result
      end

      # Log node information
      #
      # @param node [Object] Node to log information about
      # @param label [String] Label for the node
      def self.log_node(node, label: "Node")
        return unless enabled?

        # Determine type/name safely: doubles in specs sometimes set
        # `class` to a String, so guard against calling `name` on an
        # instance.
        type_name = begin
          klass = node.class
          if klass.respond_to?(:name) && klass.name
            klass.name.split("::").last
          else
            klass.to_s
          end
        rescue StandardError
          node.class.to_s
        end

        # Determine lines if the node exposes a location
        lines = nil
        if node.respond_to?(:location)
          loc = node.location
          if loc.respond_to?(:start_line) && loc.respond_to?(:end_line)
            lines = "#{loc.start_line}..#{loc.end_line}"
          elsif loc.respond_to?(:start_line)
            lines = "#{loc.start_line}"
          end
        elsif node.respond_to?(:start_line) && node.respond_to?(:end_line)
          lines = "#{node.start_line}..#{node.end_line}"
        end

        info = if defined?(FreezeNode) && node.is_a?(FreezeNode)
          {type: "FreezeNode", lines: "#{node.start_line}..#{node.end_line}"}
        else
          h = {type: type_name}
          h[:lines] = lines if lines
          h
        end

        debug(label, info)
      end
    end
  end
end
