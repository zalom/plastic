# frozen_string_literal: true

require "json"
require_relative "../../invalid"
require_relative "intent"
require_relative "../printer"
require_relative "prints"
require_relative "store_folder"
require_relative "sync_selection"
require_relative "sync/plan"
require_relative "sync/hand_edits"
require_relative "sync/file_reads"
require_relative "sync/resolution"
require_relative "sync/legacy_import"
require_relative "sync/intent_folders"
require_relative "sync/archived_intents"
require_relative "sync/old_savepoints"
require_relative "sync/declared_prints"

module Plastic
  module Graph
    module Knowledge
      # Levels a store folder and its rows in one direction. Sync up reads the
      # files people changed into rows; sync down writes the rows that changed
      # into files. A record changed on both sides since the last print is a
      # conflict, and only an overwrite settles it.
      class Sync
        def initialize(folder:, retrieval:, databases:)
          @folder = folder
          @retrieval = retrieval
          @databases = databases
        end

        # `options` may hold :overwrite and :merge, as Resolution reads them.
        def plan(direction, options = {}) = Plan.build(@folder, @retrieval, Resolution.new(direction, @folder.root, options), @databases)

        # Applies every action of `plan` but the conflicts, and says what it did, one line per file.
        def apply(plan, rollback: Legacy::ImportRollback)
          legacy = plan.legacy
          lines = legacy ? LegacyImport.new(self, @folder, @retrieval, @databases, rollback:).call : applied(plan)
          @retrieval.reindex if legacy || plan.direction == :down
          lines
        end

        def applied(plan)
          @folder.ignore_databases

          printer.record(plan.entries_for(:record).map(&:print))
          (plan.direction == :up) ? read_up(plan) : print_down(plan)
        end

        # Sync up: the rows of the folders that have none first, the archived intents the index lists, then every file
        # changed, then the rows of the paths it no longer reads go, then the index is printed again from the rows. Last,
        # the search rows of the intents whose files it read are built again, all in one pass.
        def read_up(plan)
          write_folders
          paths = plan.entries_for(:read).map(&:path) | plan.second_home.paths
          lines = read(paths) + remove_unread(plan)
          printer.print(plan.printed_up(Prints.of_store(@retrieval).to_h { |print| [print.path, print] }))
          reindex(paths)
          lines
        end

        def write_folders = [IntentFolders, ArchivedIntents].each { |rows| rows.new(@folder, @retrieval).write_to(@databases) }

        def read(paths) = file_reads.call(paths)

        def remove_unread(plan) = plan.unread.remove(@databases.fetch(:store))

        def read_all(paths) = file_reads.read_all(paths)

        def reprint(reads) = file_reads.reprint(reads)

        def print_down(plan)
          printer.print(plan.entries_for(:print).map(&:print))
          leftovers = plan.old_savepoints
          [*leftovers.remove(@folder, @databases), *leftovers.kept_lines]
        end

        # The printed files a person changed by hand, for the prints `kinds` name and the facts of the call.
        def hand_edited(kinds, facts) = HandEdits.new(@retrieval, @folder, @databases, DeclaredPrints.new(@retrieval, kinds, facts).call).call

        def printer = (@printer ||= Printer.new(@folder, @databases, @retrieval))

        private

        def reindex(paths) = @retrieval.reindex(paths.filter_map { |path| SyncSelection.intent_of(path) }.uniq)

        def file_reads = FileReads.new(folder: @folder, retrieval: @retrieval, databases: @databases, printer: printer)
      end
    end
  end
end
