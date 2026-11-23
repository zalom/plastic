# frozen_string_literal: true

require "find"
require_relative "mirror"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class Preview
          # The files of a folder that a preview compares: no backups, no databases and no sidecars.
          class Tree
            LEFT_OUT = %r{\A#{Mirror::BACKUPS}/|#{Mirror::DATABASE.source}|#{Mirror::SIDECAR.source}}

            def initialize(root)
              @root = root
            end

            def files
              return [] unless File.directory?(@root)

              Find.find(@root).select { |path| File.file?(path) }.map { |path| path.delete_prefix("#{@root}/") }.grep_v(LEFT_OUT)
            end
          end
        end
      end
    end
  end
end
