# frozen_string_literal: true

module Ast
  module Merge
    # Shared merge-facing layout abstractions.
    #
    # `Ast::Merge::Layout` models interstitial blank-line runs in a way that lets
    # adjacent nodes both be aware of the same gap while ensuring only one side
    # controls output at a time.
    module Layout
      autoload :Attachment, "ast/merge/layout/attachment"
      autoload :Augmenter, "ast/merge/layout/augmenter"
      autoload :Gap, "ast/merge/layout/gap"
    end
  end
end
