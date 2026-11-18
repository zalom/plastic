# frozen_string_literal: true

require_relative "intent_folders"
require_relative "archived_intents"
require_relative "readability"
require_relative "second_home"
require_relative "old_savepoints"
require_relative "../new_types"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Gathers what one sync would do into its Plan: the entries of the folder and the rows, and the files
        # a sync up would read, none of which a store waiting for its import reads.
        class PlanBuilder
          def initialize(folder, retrieval, resolution, databases)
            @folder = folder
            @retrieval = retrieval
            @resolution = resolution
            @databases = databases
          end

          IDLE = { archived: 0 }.freeze

          def call
            folders = legacy? ? nil : IntentFolders.new(@folder, @retrieval)
            entries = Plan.entries(@folder, @retrieval, folders)
            Plan.new(resolution: @resolution, entries:, legacy: importing?, problem:,
              unreadable: Array(folders&.problems), old_savepoints:, **(reading? ? reads(entries, folders) : IDLE))
          end

          private

          def legacy? = @folder.legacy?

          def up? = @resolution.up?

          def importing? = up? && legacy?

          def reading? = up? && !legacy?

          def problem = (Plan.legacy_problem if legacy? && !up?)

          def old_savepoints = up? ? OldSavepoints.none : OldSavepoints.find(@folder, @retrieval)

          # What only a sync up of a store that is not legacy reads: the archived intents, the second home and the files no read can take.
          def reads(entries, folders)
            second_home = SecondHome.new(@folder, @retrieval, folders)
            { archived: ArchivedIntents.new(@folder, @retrieval).missing.size, second_home:, new_types: NewTypes.new(@folder).call,
              unreadable_files: unreadable_entries(entries).merge(second_home.problems) }
          end

          # The changed files of `entries` that sync up would read and cannot.
          def unreadable_entries(entries)
            rowed = @retrieval.intents.map(&:dir)
            found = Readability.new(@folder, @retrieval, @databases).call(entries.select { |entry| entry.readable_by_up?(rowed) }.map(&:path))
            found.transform_keys { |path| Plan.owner(path) }
          end
        end
      end
    end
  end
end
