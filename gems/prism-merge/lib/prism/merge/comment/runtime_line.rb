# frozen_string_literal: true

module Prism
  module Merge
    module Comment
      # Synthetic comment line emitted from runtime child-merge reintegration
      # rather than directly replayed from the original analyzed source line.
      class RuntimeLine < Line
        def runtime_override?
          true
        end
      end
    end
  end
end
