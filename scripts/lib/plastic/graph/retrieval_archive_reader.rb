# frozen_string_literal: true

require_relative "archive"

module Plastic
  module Graph
    # Resolves archive state without mixing archive storage into the graph facade.
    class RetrievalArchiveReader
      ARCHIVE_SQL = "SELECT * FROM archives WHERE origin_id = :origin AND intent_id = :intent_id"

      def initialize(database, origin_id)
        @database = database
        @origin_id = origin_id
      end

      def archive_of(intent_id)
        row = @database.row(ARCHIVE_SQL, origin: @origin_id, intent_id:)
        row && Archive.from_h(row)
      end

      def archived?(intent_id)
        archive = archive_of(intent_id)
        !archive.nil? && archive.restored_at.nil?
      end
    end
  end
end
