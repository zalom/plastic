# frozen_string_literal: true

require "sqlite3"
require_relative "../graph/origin"
require_relative "../graph/schema"
require_relative "../graph/retrieval/reference_backfill"

module Plastic
  module Doctor
    # Whether a store's knowledge graph carries the retrieval backfill marker
    # of this installation. It reads the origin id and the database and writes
    # neither.
    class RetrievalMarker
      PROBLEM = "the retrieval backfill has not run for this installation, so search and document get refuse this store"
      BACKFILL = Graph::Retrieval::ReferenceBackfill

      def initialize(home, folder)
        @home = home
        @folder = folder
      end

      def problem = (PROBLEM unless marked?)

      private

      attr_reader :home, :folder

      def marked?
        origin = recorded_origin or return false

        SQLite3::Database.new(knowledge, readonly: true).then do |connection|
          connection.execute(BACKFILL.complete_sql, [origin, BACKFILL::SCHEMA_VERSION]).any?
        ensure
          connection.close
        end
      rescue SQLite3::Exception
        false
      end

      def knowledge = File.join(folder, Graph::Schema.file(:knowledge))

      def recorded_origin
        path = File.join(home, Graph::Origin::FILE)
        text = File.file?(path) && File.read(path).strip
        text unless text.to_s.empty?
      end
    end
  end
end
