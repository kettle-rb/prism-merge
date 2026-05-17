# frozen_string_literal: true

module Ast
  module Merge
    # Protocol module for block directive synthetic nodes.
    #
    # A block directive is an open/close comment pair that wraps content to
    # signal merge or coverage behaviour. Two built-in kinds:
    #   - :freeze  — content between markers is preserved from dest during merge
    #   - :nocov   — content between markers is excluded from coverage reporting
    #
    # Both kinds share the same structural shape:
    #   - An opening marker line
    #   - Zero or more content lines (comments, code, blank lines)
    #   - A closing marker line
    #
    # Block directives must form a clean tree:
    #   - They may be nested (a :nocov inside a :freeze, etc.)
    #   - They must NOT offset-overlap (crossing spans are invalid)
    #   - They must open and close at the same syntactic tree level
    #
    # @example Including in a class
    #   class MyDirective
    #     include Ast::Merge::BlockDirective
    #     def kind = :freeze
    #     def start_line = @start_line
    #     def end_line = @end_line
    #     def children = @nodes
    #     def merge_policy = :destination
    #   end
    module BlockDirective
      # Returns the kind of this directive.
      # Must be implemented by including class.
      # @return [Symbol] :freeze, :nocov, or a custom kind
      # @abstract
      def kind
        raise NotImplementedError, "#{self.class} must implement #kind"
      end

      # Returns the child nodes contained between the open and close markers.
      # Must be implemented by including class.
      # @return [Array] Content nodes (AST nodes, comment nodes, blank nodes)
      # @abstract
      def children
        raise NotImplementedError, "#{self.class} must implement #children"
      end

      # Returns the starting line number (the open marker line, 1-based).
      # Must be implemented by including class.
      # @return [Integer]
      # @abstract
      def start_line
        raise NotImplementedError, "#{self.class} must implement #start_line"
      end

      # Returns the ending line number (the close marker line, 1-based).
      # Must be implemented by including class.
      # @return [Integer]
      # @abstract
      def end_line
        raise NotImplementedError, "#{self.class} must implement #end_line"
      end

      # Returns the merge policy for this directive, or nil to follow file preference.
      #
      # - :destination — dest wins (e.g., :freeze blocks are user customizations)
      # - :template    — template wins
      # - nil          — follow the file's configured preference (no override)
      #
      # Must be implemented by including class.
      # @return [Symbol, nil]
      # @abstract
      def merge_policy
        raise NotImplementedError, "#{self.class} must implement #merge_policy"
      end

      # Returns true to identify this node as a block directive.
      # @return [Boolean]
      def block_directive?
        true
      end

      # Returns true if this is a freeze-kind directive.
      # @return [Boolean]
      def freeze_directive?
        kind == :freeze
      end

      # Returns true if this is a nocov-kind directive.
      # @return [Boolean]
      def nocov_directive?
        kind == :nocov
      end

      # Returns the line span of this directive as a Range.
      # @return [Range]
      def line_range
        (start_line..end_line)
      end

      # Returns true if the given line number falls within this directive.
      # @param line [Integer]
      # @return [Boolean]
      def covers_line?(line)
        line_range.cover?(line)
      end
    end
  end
end
