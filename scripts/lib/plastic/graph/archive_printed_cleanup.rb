# frozen_string_literal: true

module Plastic
  module Graph
    # Removes printed-file records for a directory that archive deletion removed.
    class ArchivePrintedCleanup
      def initialize(databases, retrieval)
        @databases = databases
        @retrieval = retrieval
      end

      def remove(dir)
        paths = retrieval.printed.keys.select { |path| path.start_with?("#{dir}/") }
        return if paths.empty?

        Schema.store.each { |key| remove_from(key, paths) }
      end

      private

      attr_reader :databases, :retrieval

      def remove_from(key, paths)
        databases.fetch(key).transaction { |batch| paths.each { |path| batch.remove(:printed, path:) } }
      end
    end
  end
end
