# frozen_string_literal: true

module Prism
  module Merge
    module Version
      VERSION = "0.1.0"

      module_function

      # rubocop:disable ThreadSafety/ClassInstanceVariable
      #
      # The logic below, through the end of the file, comes from version_gem.
      # Extracted because version_gem depends on this gem, and circular dependencies are bad.
      #
      # A Gem::Version for this version string
      #
      # Useful when you need to compare versions or pass a Gem::Version instance
      # to APIs that expect it. This is equivalent to `Gem::Version.new(to_s)`.
      #
      # @return [Gem::Version]
      def gem_version
        @gem_version ||= ::Gem::Version.new(to_s)
      end

      # The version number as a string
      #
      # @return [String]
      def to_s
        self::VERSION
      end

      # The major version
      #
      # @return [Integer]
      def major
        @major ||= _to_a[0].to_i
      end

      # The minor version
      #
      # @return [Integer]
      def minor
        @minor ||= _to_a[1].to_i
      end

      # The patch version
      #
      # @return [Integer]
      def patch
        @patch ||= _to_a[2].to_i
      end

      # The pre-release version, if any
      #
      # @return [String, NilClass]
      def pre
        @pre ||= _to_a[3]
      end

      # The version number as a hash
      #
      # @return [Hash]
      def to_h
        @to_h ||= {
          major: major,
          minor: minor,
          patch: patch,
          pre: pre,
        }
      end

      # The version number as an array of cast values
      #
      # @return [Array<[Integer, String, NilClass]>]
      def to_a
        @to_a ||= [major, minor, patch, pre]
      end

      private

      module_function

      # The version number as an array of strings
      #
      # @return [Array<String>]
      def _to_a
        @_to_a = self::VERSION.split(".")
      end
      # rubocop:enable ThreadSafety/ClassInstanceVariable
    end
    VERSION = Version::VERSION # traditional location
  end
end
