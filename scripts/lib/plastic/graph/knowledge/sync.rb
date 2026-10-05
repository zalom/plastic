# frozen_string_literal: true

require "json"
require_relative "../../invalid"
require_relative "intent"
require_relative "../printer"
require_relative "../prints"
require_relative "reader"
require_relative "../schema"
require_relative "store_folder"
require_relative "sync/plan"
require_relative "sync/resolution"
require_relative "sync/legacy_import"
require_relative "sync/intent_folders"

module Plastic
  module Graph
    module Knowledge
      # Levels a store folder and its rows in one direction. Sync up reads the
      # files people changed into rows; sync down prints the rows that changed
      # into files. A record changed on both sides since the last print is a
      # conflict, and only an overwrite settles it.
      class Sync
        def initialize(folder:, retrieval:, databases:)
          @folder = folder
          @retrieval = retrieval
          @databases = databases
        end

        # `options` may hold :overwrite and :merge, as Resolution reads them.
        def plan(direction, options = {}) = Plan.build(@folder, @retrieval, Resolution.new(direction, @folder.root, options))

        # Applies every action of `plan` but the conflicts, and says what it did, one line per file.
        def apply(plan)
          @folder.ignore_databases
          return LegacyImport.new(self, @folder, @retrieval, @databases).call if plan.legacy

          printer.record(plan.taking(:record).map(&:print))
          (plan.direction == :up) ? read_up(plan) : print(plan.taking(:print).map(&:print))
        end

        # Sync up: the rows of the folders that have none first, then every file
        # changed, then the index printed again from the rows.
        def read_up(plan)
          write_folder_intents
          lines = read(plan.taking(:read).map(&:path))
          printer.print([Prints.index(@retrieval)])
          lines
        end

        # Reads files into rows, one transaction per database, then prints
        # each back from its rows, so the file holds the form the rows print.
        def read(paths)
          reads = paths.map(&reader.method(:read))
          write_reads(reads)
          reprint(reads)
          reads.map(&:line)
        end

        def print(prints) = printer.print(prints).map { |path| "printed #{path}" }

        def printer = (@printer ||= Printer.new(@folder, @databases, @retrieval))

        private

        def reader = Reader.new(@folder, known_intents, @retrieval.origin_id, retrieval: @retrieval)

        # The work graph first, so a new intent's row is in place before its files.
        def write_reads(reads)
          reads.group_by(&:database).sort_by { |key, _group| Schema.store.index(key) }.each do |key, group|
            write_group(key, group)
          end
        end

        def write_group(key, group)
          applies = group.map(&:apply)
          @databases.fetch(key).transaction { |batch| batch.apply(applies) }
        end

        def reprint(reads)
          fresh = Prints.of_store(@retrieval).to_h { |print| [print.path, print] }
          printer.print(reads.map { |found| fresh[found.path] || found.kept_print(@folder) })
        end

        # The intents of the rows. store/index.json is never read for them: the folders are.
        def known_intents = @retrieval.intents.to_h { |intent| [intent.intent_id, intent] }

        def write_folder_intents
          rows = IntentFolders.new(@folder, @retrieval).intents.map(&:new_row)
          @databases.fetch(:work).transaction { |batch| batch.put_all(:intents, rows) } if rows.any?
        end
      end
    end
  end
end
