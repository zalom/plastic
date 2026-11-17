# frozen_string_literal: true

require_relative "entry_list"
require_relative "resolution"
require_relative "intent_folders"
require_relative "../store_folder"
require_relative "archived_intents"
require_relative "readability"
require_relative "second_home"
require_relative "old_savepoints"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # What one sync would do, before it does anything. `legacy` marks a
        # store whose INDEX.md waits to be imported, `problem` a call that
        # cannot run, `archived` the archived intents the index lists that have no row, and `unreadable` the intent folders no row can be read
        # from, one line each. The files of those folders are no entries.
        # `unreadable_files` maps each changed file that a sync up cannot read into rows to the reason.
        Plan = Data.define(:resolution, :entries, :legacy, :problem, :unreadable, :archived, :unreadable_files, :second_home, :old_savepoints) do
          def initialize(unreadable_files: {}, second_home: SecondHome::NONE, old_savepoints: OldSavepoints.none, **fields) = super
        end

        # Each entry's action, and what the sync writes.
        class Plan
          def self.build(folder, retrieval, resolution, databases)
            legacy = folder.legacy?
            up = resolution.up?
            folders = legacy ? nil : IntentFolders.new(folder, retrieval)
            entries = entries(folder, retrieval, folders)
            second_home = second_home_of(folder, retrieval, folders, up && !legacy)
            new(resolution:, entries:, legacy: up && legacy,
              problem: down_problem(legacy, up), unreadable: Array(folders&.problems),
              archived: archived(folder, retrieval, resolution), second_home:, old_savepoints: old_savepoints(folder, retrieval, up),
              unreadable_files: unreadable_files_of(Readability.new(folder, retrieval, databases), entries, retrieval, up && !legacy, second_home))
          end

          def self.old_savepoints(folder, retrieval, up) = up ? OldSavepoints.none : OldSavepoints.find(folder, retrieval)

          def self.down_problem(legacy, up) = (legacy_problem if legacy && !up)

          def self.second_home_of(folder, retrieval, folders, reads) = reads ? SecondHome.new(folder, retrieval, folders) : SecondHome::NONE

          # Only a sync up of a store that is not legacy reads files.
          def self.unreadable_files_of(readability, entries, retrieval, reads, second_home)
            reads ? unreadable_files(readability, retrieval, entries).merge(second_home.problems) : {}
          end

          # The changed files of `entries` that sync up would read and cannot.
          def self.unreadable_files(readability, retrieval, entries)
            rowed = retrieval.intents.map(&:dir)
            found = readability.call(entries.select { |entry| readable?(entry, rowed) }.map(&:path))
            found.transform_keys { |path| owner(path) }
          end

          # The file a path belongs to: the clusters and the links are parts of the index.
          def self.owner(path) = Prints::Parts.path?(path) ? StoreFolder::INDEX : path

          # A changed file of an intent that has its rows, or an index a person changed after its print; the files of a folder without rows read after its row is written.
          def self.readable?(entry, rowed)
            path = entry.path
            return path == StoreFolder::INDEX && entry.hand_edited? && !entry.rows_sha.nil? if entry.generated?

            %i[read conflict].include?(entry.action(:up)) && readable_path?(path, rowed)
          end

          def self.readable_path?(path, rowed)
            StoreFolder.roadmap?(path) || Prints::Parts.path?(path) || rowed.any? { |dir| path.start_with?("#{dir}/") }
          end

          def self.entries(folder, retrieval, folders = nil) = EntryList.new(folder, retrieval, folders).entries

          def self.on_disk(folder, folders = nil) = EntryList.new(folder, nil, folders).on_disk

          def self.archived(folder, retrieval, resolution) = (resolution.up? && !folder.legacy?) ? ArchivedIntents.new(folder, retrieval).missing.size : 0

          def self.legacy_problem = "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first"

          def direction = resolution.direction

          # The unreadable files of a second home: this home holds no rows that could print them again.
          def rowless_files = second_home.problems.keys

          # Each path with its action, a conflict the overwrite names resolved.
          def actions = entries.to_h { |entry| [entry, settled(entry)] }

          def conflicts = actions.select { |_entry, action| action == :conflict }.keys.map(&:path)

          def entries_for(action) = actions.select { |_entry, found| found == action }.keys

          # The records this sync writes; zero when the folder and the rows are level.
          def pending = actions.values.count { |action| %i[record read print].include?(action) } + (legacy ? 1 : 0) + archived + second_home_extra + old_savepoints.removable.size

          # The reads of a second home that no entry already counts.
          def second_home_extra = second_home.size - (second_home.paths & entries_for(:read).map(&:path)).size

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
            return :none if unreadable_files.key?(Plan.owner(path))

            action = entry.action(direction)
            return resolution.side if action == :conflict && resolution.overwrites?(path)

            named_print?(entry) ? :print : action
          end

          # The index prints from the rows when another home printed it and this home holds no print of it. An index
          # that a person changed and that has rows is read into rows. When it cannot be read, it is kept as written
          # if this home holds a print of it, and printed from the rows if not. Any other index is left as it is.
          def generated_up(entry)
            return :print if entry.reprinted?
            return :none unless entry.hand_edited? && entry.rows_sha
            return :read unless unreadable_files.key?(entry.path)

            entry.printed_sha ? :none : :print
          end

          # An overwrite that names this path prints it from its rows when the file differs from them.
          def named_print?(entry) = direction == :down && resolution.names?(entry.path) && entry.rows_sha && !entry.level?
        end
      end
    end
  end
end
