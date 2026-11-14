# frozen_string_literal: true

require_relative "entry_list"
require_relative "resolution"
require_relative "intent_folders"
require_relative "../store_folder"
require_relative "archived_intents"
require_relative "readability"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # What one sync would do, before it does anything. `legacy` marks a
        # store whose INDEX.md waits to be imported, `problem` a call that
        # cannot run, `archived` the archived intents the index lists that have no row, and `unreadable` the intent folders no row can be read
        # from, one line each. The files of those folders are no entries.
        # `unreadable_files` maps each changed file that a sync up cannot read into rows to the reason.
        Plan = Data.define(:resolution, :entries, :legacy, :problem, :unreadable, :archived, :unreadable_files) do
          def initialize(unreadable_files: {}, **fields) = super
        end

        # Each entry's action, and what the sync writes.
        class Plan
          def self.build(folder, retrieval, resolution)
            legacy = folder.legacy?
            folders = legacy ? nil : IntentFolders.new(folder, retrieval)
            entries = entries(folder, retrieval, folders)
            new(resolution:, entries:, unreadable: Array(folders&.problems),
              archived: archived(folder, retrieval, resolution),
              unreadable_files: unreadable_files_of(Readability.new(folder, retrieval), entries, (resolution.up? && !legacy)),
              **legacy_facts(legacy, resolution))
          end

          # The legacy flag and the problem of a store, by what the call does.
          def self.legacy_facts(legacy, resolution)
            up = resolution.up?
            { legacy: up && legacy, problem: (legacy_problem if legacy && !up) }
          end

          # Only a sync up of a store that is not legacy reads files.
          def self.unreadable_files_of(readability, entries, reading) = reading ? readability.unreadable(entries) : {}

          def self.entries(folder, retrieval, folders = nil) = EntryList.new(folder, retrieval, folders).entries

          def self.on_disk(folder, folders = nil) = EntryList.new(folder, nil, folders).on_disk

          def self.archived(folder, retrieval, resolution) = (resolution.up? && !folder.legacy?) ? ArchivedIntents.new(folder, retrieval).missing.size : 0

          def self.legacy_problem = "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first"

          def direction = resolution.direction

          # Each path with its action, a conflict the overwrite names resolved.
          def actions = entries.to_h { |entry| [entry, settled(entry)] }

          def conflicts = actions.select { |_entry, action| action == :conflict }.keys.map(&:path)

          def taking(action) = actions.select { |_entry, found| found == action }.keys

          # The records this sync writes; zero when the folder and the rows are level.
          def pending = actions.values.count { |action| %i[record read print].include?(action) } + (legacy ? 1 : 0) + archived

          def merging? = resolution.merging?

          # The unreadable files that sync up leaves as they are: a generated one prints again from its rows instead.
          def left_unreadable = unreadable_files.reject { |path, _reason| Entry.generated?(path) }

          # A call that cannot run: a store not imported yet, or an overwrite path that names nothing.
          def failure
            return problem if problem

            unknown = resolution.unknown_path(entries.map(&:path))
            "#{unknown} names no file and no rows of this store" if unknown
          end

          private

          def settled(entry) = entry.settle(resolution, unreadable_files)
        end
      end
    end
  end
end
