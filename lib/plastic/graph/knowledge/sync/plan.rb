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
          def self.build(folder, retrieval, resolution, databases = nil)
            legacy = folder.legacy?
            up = resolution.up?
            folders = legacy ? nil : IntentFolders.new(folder, retrieval)
            entries = entries(folder, retrieval, folders)
            new(resolution:, entries:, legacy: up && legacy,
              problem: (legacy_problem if legacy && !up), unreadable: Array(folders&.problems),
              archived: archived(folder, retrieval, resolution),
              unreadable_files: unreadable_files_of(Readability.new(folder, retrieval, databases), entries, retrieval, up && !legacy))
          end

          # Only a sync up of a store that is not legacy reads files.
          def self.unreadable_files_of(readability, entries, retrieval, reads)
            reads ? unreadable_files(readability, retrieval, entries) : {}
          end

          # The changed files of `entries` that sync up would read and cannot.
          def self.unreadable_files(readability, retrieval, entries)
            rowed = retrieval.intents.map(&:dir)
            readability.call(entries.select { |entry| readable?(entry, rowed) }.map(&:path))
          end

          # A changed file that is the index, a hand edited generated file with rows, or belongs to an intent that has its rows; the files of a folder without rows read after its row is written.
          def self.readable?(entry, rowed)
            path = entry.path
            return true if path == StoreFolder::INDEX && %i[read conflict].include?(entry.action(:up))
            return entry.hand_edited? && !entry.rows_sha.nil? if entry.generated?

            %i[read conflict].include?(entry.action(:up)) && rowed.any? { |dir| path.start_with?("#{dir}/") }
          end

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

          # A call that cannot run: a store not imported yet, or an overwrite path that names nothing.
          def failure
            return problem if problem

            unknown = resolution.unknown_path(entries.map(&:path))
            "#{unknown} names no file and no rows of this store" if unknown
          end

          private

          def settled(entry)
            return generated_up(entry) if direction == :up && entry.generated?
            path = entry.path
            return :none if unreadable_files.key?(path)

            action = entry.action(direction)
            return resolution.side if action == :conflict && resolution.overwrites?(path)

            named_print?(entry) ? :print : action
          end

          # A generated file a person changed is read when it can be and kept as written when it cannot.
          def generated_up(entry)
            return :none unless entry.hand_edited? && entry.rows_sha

            unreadable_files.key?(entry.path) ? :none : :read
          end

          # An overwrite that names this path prints it from its rows when the file differs from them.
          def named_print?(entry) = direction == :down && resolution.names?(entry.path) && entry.rows_sha && !entry.level?
        end
      end
    end
  end
end
