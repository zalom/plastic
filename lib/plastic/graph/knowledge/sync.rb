# frozen_string_literal: true

require "json"
require_relative "../../invalid"
require_relative "intent"
require_relative "../printer"
require_relative "../prints"
require_relative "store_folder"
require_relative "sync/plan"
require_relative "sync/file_reads"
require_relative "sync/resolution"
require_relative "sync/legacy_import"
require_relative "sync/intent_folders"

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
        def plan(direction, options = {}) = Plan.build(@folder, @retrieval, Resolution.new(direction, @folder.root, options))

        # Applies every action of `plan` but the conflicts, and says what it did, one line per file.
        def apply(plan)
          @folder.ignore_databases
          return LegacyImport.new(self, @folder, @retrieval, @databases).call if plan.legacy

          printer.record(plan.taking(:record).map(&:print))
          (plan.direction == :up) ? read_up(plan) : print_down(plan)
        end

        # Sync up: the rows of the folders that have none first, then every file
        # changed, then the index printed again from the rows.
        def read_up(plan)
          IntentFolders.new(@folder, @retrieval).write_to(@databases)
          lines = read(plan.taking(:read).map(&:path))
          printer.print([Prints.index(@retrieval)])
          lines
        end

        def read(paths) = FileReads.new(folder: @folder, retrieval: @retrieval, databases: @databases, printer: printer).call(paths)

        def print_down(plan)
          printer.print(plan.taking(:print).map(&:print))
          []
        end

        def printer = (@printer ||= Printer.new(@folder, @databases, @retrieval))
      end
    end
  end
end
