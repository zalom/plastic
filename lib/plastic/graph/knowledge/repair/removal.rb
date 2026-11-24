# frozen_string_literal: true

require_relative "../resources/move"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # One file a repair removes, by path relative to the store folder, with the rows that held it.
        Removal = Data.define(:path) do
          def intent_id = SyncSelection.intent_of(path)

          # The path inside the intent folder.
          def inside = Resources::Move.inside(path)

          # The folder of the intent, store/{id}--{slug}.
          def dir = path.delete_suffix("/#{inside}")

          # The fields the row drop of Resources::RowMoves reads: the file is both the source and the target.
          def row = [intent_id, inside, inside, path, path]

          def preview = "preview: remove #{path}"

          def line = "removed #{path}"
        end
      end
    end
  end
end
