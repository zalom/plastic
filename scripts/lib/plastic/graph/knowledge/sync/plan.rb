# frozen_string_literal: true

require_relative "entry_list"
require_relative "resolution"
require_relative "intent_folders"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # What one sync would do, before it does anything. `legacy` marks a
        # store whose INDEX.md waits to be imported, `problem` a call that
        # cannot run, and `unreadable` the intent folders no row can be read
        # from, one line each. The files of those folders are no entries.
        Plan = Data.define(:resolution, :entries, :legacy, :problem, :unreadable)

        # Each entry's action, and what the sync writes.
        class Plan
          def initialize(resolution:, entries:, legacy:, problem:, unreadable: [])
            super
          end

          def self.build(folder, retrieval, resolution)
            legacy = folder.legacy?
            up = resolution.up?
            folders = legacy ? nil : IntentFolders.new(folder, retrieval)
            new(resolution:, entries: entries(folder, retrieval, folders), legacy: up && legacy,
              problem: (legacy_problem if legacy && !up), unreadable: folders&.problems || [])
          end

          def self.entries(folder, retrieval, folders = nil) = EntryList.new(folder, retrieval, folders).entries

          def self.on_disk(folder, folders = nil) = EntryList.new(folder, nil, folders).on_disk

          def self.legacy_problem = "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first"

          def direction = resolution.direction

          # Each path with its action, a conflict the overwrite names resolved.
          def actions = entries.to_h { |entry| [entry, settled(entry)] }

          def conflicts = actions.select { |_entry, action| action == :conflict }.keys.map(&:path)

          def taking(action) = actions.select { |_entry, found| found == action }.keys

          # The records this sync writes; zero when the folder and the rows are level.
          def pending = actions.values.count { |action| %i[record read print].include?(action) } + (legacy ? 1 : 0)

          def merging? = resolution.merging?

          # A call that cannot run: a store not imported yet, or an overwrite path that names nothing.
          def failure
            return problem if problem

            unknown = resolution.unknown_path(entries.map(&:path))
            "#{unknown} names no file and no rows of this store" if unknown
          end

          private

          def settled(entry)
            return :none if direction == :up && entry.generated?

            action = entry.action(direction)
            (action == :conflict && resolution.overwrites?(entry.path)) ? resolution.side : action
          end
        end
      end
    end
  end
end
