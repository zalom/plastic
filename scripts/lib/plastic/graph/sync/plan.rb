# frozen_string_literal: true

require_relative "entry"
require_relative "../prints"
require_relative "../store_folder"

module Plastic
  module Graph
    class Sync
      # What one sync would do, before it does anything. `overwrite` is false
      # for none, nil for every conflict, or the path of one record, and a
      # conflict it names takes the direction's side. `legacy` marks a store
      # whose INDEX.md waits to be imported.
      Plan = Data.define(:direction, :entries, :overwrite, :merge, :legacy, :problem) do
        def self.build(folder, retrieval, direction:, overwrite: false, merge: false)
          overwrite = overwrite.delete_prefix("#{folder.root}/") if overwrite.is_a?(String)
          new(direction:, entries: entries(folder, retrieval), overwrite:, merge:,
            legacy: direction == :up && folder.legacy?, problem: legacy_problem(folder, direction))
        end

        def self.entries(folder, retrieval)
          prints = Prints.of_store(retrieval).to_h { |print| [print.path, print] }
          printed = retrieval.printed
          (prints.keys | on_disk(folder) | printed.keys).sort.map do |path|
            Entry.new(path, folder.sha256(path), printed[path], prints[path])
          end
        end

        def self.on_disk(folder) = [*(StoreFolder::INDEX if folder.exist?(StoreFolder::INDEX)), *folder.intent_files]

        def self.legacy_problem(folder, direction)
          return unless direction == :down && folder.legacy?

          "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first"
        end

        # Each path with its action, a conflict the overwrite names resolved.
        def actions
          entries.to_h do |entry|
            action = entry.action(direction)
            [entry, (action == :conflict && overwritten?(entry)) ? side : action]
          end
        end

        def side = (direction == :up) ? :read : :print

        def overwritten?(entry) = overwrite.nil? || overwrite == entry.path

        def conflicts = actions.select { |_entry, action| action == :conflict }.keys.map(&:path)

        def taking(action) = actions.select { |_entry, found| found == action }.keys

        # The records this sync writes; zero when the folder and the rows are level.
        def pending = actions.values.count { |action| %i[record read print].include?(action) } + (legacy ? 1 : 0)

        # One-sided changes go through while conflicts wait: --merge, or --overwrite PATH.
        def merging? = merge || overwrite.is_a?(String)

        # A call that cannot run: an overwrite path that names nothing, or a store not imported yet.
        def failure
          return problem if problem
          return unless overwrite.is_a?(String) && entries.none? { |entry| entry.path == overwrite }

          "#{overwrite} names no file and no rows of this store"
        end
      end
    end
  end
end
