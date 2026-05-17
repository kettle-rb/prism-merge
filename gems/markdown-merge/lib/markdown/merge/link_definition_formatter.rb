# frozen_string_literal: true

module Markdown
  module Merge
    # Formats link reference definitions for output.
    #
    # Markdown parsers (especially cmark-based ones like Markly/Commonmarker)
    # consume link reference definitions during parsing and resolve them into
    # inline links. This means they don't appear as nodes in the AST.
    #
    # This formatter reconstructs the markdown syntax from LinkDefinitionNode
    # instances so they can be included in the merged output.
    #
    # @example
    #   node = LinkDefinitionNode.new(
    #     "[ref]: https://example.com \"Title\"",
    #     label: "ref",
    #     url: "https://example.com",
    #     title: "Title"
    #   )
    #   LinkDefinitionFormatter.format(node)
    #   # => "[ref]: https://example.com \"Title\""
    module LinkDefinitionFormatter
      class << self
        # Format a link definition node
        #
        # @param node [LinkDefinitionNode] The link definition node
        # @return [String] Formatted link definition
        def format(node)
          return node.content if node.content && !node.content.empty?

          # Reconstruct from components
          output = "[#{node.label}]: #{node.url}"
          output += " \"#{node.title}\"" if node.title && !node.title.empty?
          output
        end

        # Format multiple link definitions
        #
        # @param nodes [Array<LinkDefinitionNode>] Link definition nodes
        # @param separator [String] Separator between definitions
        # @return [String] Formatted link definitions
        def format_all(nodes, separator: "\n")
          nodes.map { |node| format(node) }.join(separator)
        end
      end
    end
  end
end
