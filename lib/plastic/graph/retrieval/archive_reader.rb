# frozen_string_literal: true

require_relative "source_reader"

module Plastic
  module Graph
    module Retrieval
      # Reads archive state and the files an archive keeps for one origin.
      class ArchiveReader < SourceReader
        ARCHIVE_SQL = "SELECT * FROM archives WHERE origin_id = :origin AND intent_id = :intent_id"

        ACTIVE_SQL = "#{ARCHIVE_SQL} AND restored_at IS NULL"

        def archived?(intent_id) = databases.fetch(:store).rows(ACTIVE_SQL, origin: origin_id, intent_id:).any?
        def rows(intent_id = nil) = read(:archives, intent_id)
        def kept_files(intent_id = nil) = read(:kept_files, intent_id)
      end
    end
  end
end
