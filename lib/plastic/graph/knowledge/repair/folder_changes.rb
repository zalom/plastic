# frozen_string_literal: true

require_relative "change"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The structural changes a repair makes in one intent folder `dir`: the files it renames, the files it moves and
        # the files it removes, each kind with the reason the layout gives. A closed intent records them all as one
        # `amended` line. The files of an old actions/ folder move as one change, named by the folder they land in.
        class FolderChanges
          WHOLE = "actions/"
          VERBS = { rename: "renamed", move: "moved", remove: "removed", rebuild: "rebuilt" }.freeze

          attr_reader :dir

          # `renamed` and `moved` hold moves, `removed` the paths inside the folder of the files that go.
          def initialize(dir, renamed:, moved:, removed:, rebuilt: [])
            @dir = dir
            @changes = { rename: renamed.map { |move| pair(move) }, move: moved.map { |move| pair(move) }.uniq, remove: removed, rebuild: rebuilt }.transform_values(&:sort)
          end

          # The number of changes of each kind.
          def counts = @changes.transform_values(&:size)

          # Each kind in turn, its changes and the reason the layout gives for it.
          def text = @changes.reject { |_, items| items.empty? }.map { |kind, items| "#{VERBS.fetch(kind)} #{items.join(", ")} (#{Layout.amendment_reason(kind)})" }.join("; ")

          # The one `amended` line of the folder, with the time of the repair and no file of its own.
          def change = Change.new(intent_id: SyncSelection.intent_of(dir), dir:, text:, path: "", at: nil)

          private

          def pair(move)
            from = move.inside_from
            return "#{from} to #{move.inside_to}" unless from.start_with?(WHOLE)

            "#{WHOLE} to #{move.inside_to.delete_suffix(from.delete_prefix(WHOLE))}"
          end
        end
      end
    end
  end
end
