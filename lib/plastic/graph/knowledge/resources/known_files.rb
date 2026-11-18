# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Resources
        # The files of a store folder as a set of paths relative to it; a path that leaves the folder is not in it.
        KnownFiles = Data.define(:folder) do
          def include?(path) = !path.start_with?("..") && folder.exist?(path)
        end
      end
    end
  end
end
