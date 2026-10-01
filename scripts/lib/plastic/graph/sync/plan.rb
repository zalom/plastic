# frozen_string_literal: true

require_relative "entry"
require_relative "resolution"
require_relative "../prints"
require_relative "../store_folder"

module Plastic
  module Graph
    class Sync
      # What one sync would do, before it does anything. `legacy` marks a
      # store whose INDEX.md waits to be imported, and `problem` a call that
      # cannot run.
      Plan = Data.define(:resolution, :entries, :legacy, :problem)

      # Each entry's action, and what the sync writes.
      class Plan
        def self.build(folder, retrieval, resolution)
          legacy = folder.legacy?
          up = resolution.up?
          new(resolution:, entries: entries(folder, retrieval), legacy: up && legacy,
            problem: (legacy_problem if legacy && !up))
        end

        def self.entries(folder, retrieval)
          prints = Prints.of_store(retrieval).to_h { |print| [print.path, print] }
          printed = retrieval.printed
          (prints.keys | on_disk(folder) | printed.keys).sort.map do |path|
            Entry.new(path, folder.digest(path), printed[path], prints.fetch(path, Entry::NO_PRINT))
          end
        end

        def self.on_disk(folder) = [*(StoreFolder::INDEX if folder.exist?(StoreFolder::INDEX)), *folder.intent_files]

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
          action = entry.action(direction)
          (action == :conflict && resolution.overwrites?(entry.path)) ? resolution.side : action
        end
      end
    end
  end
end
