# frozen_string_literal: true

module Plastic
  module Graph
    # Prints files from rows: writes each file whose bytes differ from its
    # rows, and records the hash of every print in the `printed` table of the
    # database that owns the rows. The next call compares a file with that
    # hash to know whether it changed by hand.
    class Printer
      def initialize(folder, databases, retrieval)
        @folder = folder
        @databases = databases
        @retrieval = retrieval
      end

      # The paths it wrote.
      def print(prints)
        written = prints.reject { |print| @folder.sha256(print.path) == print.sha256 }
        written.each { |print| @folder.write(print.path, print.text) }
        record(prints)
        written.map(&:path)
      end

      # Records the hash of each print, so the next sync knows the file is level.
      def record(prints)
        recorded = @retrieval.printed
        fresh = prints.reject { |print| recorded[print.path] == print.sha256 }
        fresh.group_by(&:database).each do |key, group|
          @databases.fetch(key).transaction do |batch|
            group.each { |print| batch.put(:printed, { path: print.path, sha256: print.sha256, at: Plastic.now }, count: false) }
          end
        end
      end
    end
  end
end
