# frozen_string_literal: true

require "find"
require_relative "mirror"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class Preview
          # The files of a folder that a preview compares: no databases and no sidecars.
          class Tree
            def initialize(root)
              @root = root
            end

            def files
              return [] unless File.directory?(@root)

              Find.find(@root).select { |path| File.file?(path) && !path.match?(Mirror::DATABASE) && !path.match?(Mirror::SIDECAR) }.map { |path| path.delete_prefix("#{@root}/") }
            end
          end
        end
      end
    end
  end
end
