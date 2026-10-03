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
        keys = printed_keys(dir)
        Schema.store.each { |key| remove_from(key, keys) } unless keys.empty?
      end

      private

      attr_reader :databases, :retrieval

      def printed_keys(dir)
        retrieval.printed.keys.select { |path| path.start_with?("#{dir}/") }.map { |path| { path: } }
      end

      def remove_from(key, keys)
        databases.fetch(key).transaction { |batch| batch.remove_all(:printed, keys) }
      end
    end
  end
end
