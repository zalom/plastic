# frozen_string_literal: true

require_relative "entry_list"
require_relative "plan_builder"
require_relative "resolution"
require_relative "intent_folders"
require_relative "../store_folder"
require_relative "archived_intents"
require_relative "readability"
require_relative "second_home"
require_relative "old_savepoints"
require_relative "unread_rows"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # What one sync would do, before it does anything. `legacy` marks a
        # store whose INDEX.md waits to be imported, `problem` a call that
        # cannot run, `archived` the archived intents the index lists that have no row, and `unreadable` the intent folders no row can be read
        # from, one line each. The files of those folders are no entries.
        # `unreadable_files` maps each changed file that a sync up cannot read into rows to the reason. `new_types` are the file types a sync up skips and has not told about yet. `unread` holds the rows of the paths the sync no longer reads.
        Plan = Data.define(:resolution, :entries, :legacy, :problem, :unreadable, :archived, :unreadable_files, :second_home, :old_savepoints, :new_types, :unread) do
          def initialize(unreadable_files: {}, second_home: SecondHome::NONE, old_savepoints: OldSavepoints.none, new_types: [], unread: UnreadRows.none, **fields) = super
        end

        # Each entry's action, and what the sync writes.
        class Plan
          def self.build(folder, retrieval, resolution, databases) = PlanBuilder.new(folder, retrieval, resolution, databases).call

          # The file a path belongs to: the clusters and the links are parts of the index.
          def self.owner(path) = Prints::Parts.path?(path) ? StoreFolder::INDEX : path

          def self.entries(folder, retrieval, folders = nil) = EntryList.new(folder, retrieval, folders).entries

          def self.on_disk(folder, folders = nil) = EntryList.new(folder, nil, folders).on_disk

          def self.legacy_problem = "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic store sync up to import it first"

          def direction = resolution.direction

          # The unreadable files of a second home: this home holds no rows that could print them again.
          def rowless_files = second_home.problems.keys

          # Each path with its action, a conflict the overwrite names resolved.
          def actions = entries.to_h { |entry| [entry, settled(entry)] }

          def conflicts = actions.select { |_entry, action| action == :conflict }.keys.map(&:path)

          def entries_for(action) = actions.select { |_entry, found| found == action }.keys

          # The records this sync writes; zero when the folder and the rows are level.
          def pending = actions.values.count { |action| %i[record read print].include?(action) } + (legacy ? 1 : 0) + archived + beyond_entries

          # The writes a sync makes beyond its entries: the second home, the old savepoint files and the unread paths.
          def beyond_entries = second_home_extra + old_savepoints.removable.size + unread.size

          # The reads of a second home that no entry already counts.
          def second_home_extra = second_home.size - (second_home.paths & entries_for(:read).map(&:path)).size

          def merging? = resolution.merging?

          # A call that cannot run: a store not imported yet, or an overwrite path that names nothing.
          def failure
            return problem if problem

            unknown = resolution.unknown_path(entries.map(&:path))
            "#{unknown} names no file and no rows of this store" if unknown
          end

          # The index, and every file the plan prints, from the rows as the reads left them; `fresh` maps each path to its print.
          def printed_up(fresh)
            wanted = entries_for(:print).map { |entry| fresh.fetch(entry.path, entry.print) }
            index = fresh[StoreFolder::INDEX] unless unreadable_files.key?(StoreFolder::INDEX)
            [index, *wanted].compact.uniq(&:path)
          end

          private

          def settled(entry)
            return entry.generated_up(unreadable_files) if direction == :up && entry.generated?
            return :none if unreadable?(entry)

            action = entry.action(direction)
            return resolution.side if action == :conflict && resolution.overwrites?(entry.path)

            named_print?(entry) ? :print : action
          end

          def unreadable?(entry) = unreadable_files.key?(Plan.owner(entry.path))

          # An overwrite that names this path prints it from its rows when the file differs from them.
          def named_print?(entry) = direction == :down && resolution.names?(entry.path) && entry.reprintable?
        end
      end
    end
  end
end
