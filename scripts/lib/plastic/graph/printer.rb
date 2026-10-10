# frozen_string_literal: true

module Plastic
  module Graph
    # Prints files from rows: writes each file whose bytes differ from its
    # rows, and records the hash of every print in the `printed` table of the
    # database that owns the rows. The next call compares a file with that
    # hash to know whether it changed by hand.
    class Printer
      attr_reader :written

      def initialize(folder, databases, retrieval)
        @folder = folder
        @databases = databases
        @retrieval = retrieval
        @written = []
      end

      def print(prints)
        paths = prints.reject { |print| print.level?(@folder) }.each { |print| print.write_to(@folder) }.map(&:path)
        record(prints)
        remember(paths)
      end

      # Records the hash of each print, so the next sync knows the file is level.
      def record(prints)
        recorded = @retrieval.printed
        fresh = prints.reject { |print| print.recorded?(recorded) }
        fresh.group_by(&:database).each { |key, group| record_in(key, group.map(&:printed_row)) }
      end

      private

      def remember(paths)
        @written |= paths
        paths
      end

      def record_in(key, rows) = @databases.fetch(key).transaction { |batch| batch.put_all(:printed, rows) }
    end
  end
end
