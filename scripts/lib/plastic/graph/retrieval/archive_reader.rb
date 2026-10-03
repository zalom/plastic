# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Resolves archive state without mixing archive storage into the graph facade.
      class ArchiveReader
        ARCHIVE_SQL = "SELECT * FROM archives WHERE origin_id = :origin AND intent_id = :intent_id"

        ACTIVE_SQL = "#{ARCHIVE_SQL} AND restored_at IS NULL"

        def initialize(database, origin_id)
          @database = database
          @origin_id = origin_id
        end

        def archived?(intent_id) = @database.rows(ACTIVE_SQL, origin: @origin_id, intent_id:).any?
      end
    end
  end
end
