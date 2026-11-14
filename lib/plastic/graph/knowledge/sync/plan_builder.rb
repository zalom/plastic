# frozen_string_literal: true

require_relative "entry_list"
require_relative "intent_folders"
require_relative "archived_intents"
require_relative "readability"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Gathers the facts of one sync call and builds its Plan.
        class PlanBuilder
          LEGACY_PROBLEM = "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first"

          def initialize(folder, retrieval, resolution)
            @folder = folder
            @retrieval = retrieval
            @resolution = resolution
            @legacy = folder.legacy?
            @folders = @legacy ? nil : IntentFolders.new(folder, retrieval)
          end

          def call
            entries = EntryList.new(@folder, @retrieval, @folders).entries
            Plan.new(resolution: @resolution, entries:, unreadable: Array(@folders&.problems), archived:,
              unreadable_files: unreadable_files(entries), **legacy_facts)
          end

          private

          # The legacy flag and the problem of a store, by what the call does.
          def legacy_facts
            up = @resolution.up?
            { legacy: up && @legacy, problem: (LEGACY_PROBLEM if @legacy && !up) }
          end

          def archived = (reading? ? ArchivedIntents.new(@folder, @retrieval).missing.size : 0)

          # Only a sync up of a store that is not legacy reads files.
          def reading? = @resolution.up? && !@legacy

          def unreadable_files(entries) = reading? ? Readability.new(@folder, @retrieval).unreadable(entries) : {}
        end
      end
    end
  end
end
