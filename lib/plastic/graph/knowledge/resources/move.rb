# frozen_string_literal: true

require "fileutils"
require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # One file that moves, from a path to a path, both relative to the store folder.
        Move = Data.define(:from, :to) do
          def reverse = Move.new(to, from)

          def self.inside(path) = path[%r{\Astore/[^/]*--[^/]*/(.+)\z}, 1]

          def intent_id = SyncSelection.intent_of(from)

          def inside_from = Move.inside(from)

          def inside_to = Move.inside(to)

          def row = [intent_id, inside_from, inside_to, from, to]

          def onto_same_bytes?(folder) = folder.exist?(to) && folder.digest(to) == folder.digest(from)

          def onto_other_bytes?(folder) = folder.exist?(to) && folder.digest(to) != folder.digest(from)

          def refusal = "#{to} already holds other bytes than #{from}; move one of them away, then run plastic resources sort again"

          def relocate(folder, rename)
            target = folder.path(to)
            FileUtils.mkdir_p(File.dirname(target))
            rename.call(folder.path(from), target)
          end
        end
      end
    end
  end
end
