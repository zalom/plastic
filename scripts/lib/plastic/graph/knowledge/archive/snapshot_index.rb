# frozen_string_literal: true

require_relative "../archive"
require_relative "../../retrieval/evidence/writer"
require_relative "../../retrieval/evidence/text"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Adds searchable text from a durable archive snapshot to retrieval evidence.
        class SnapshotIndex
          def initialize(database, origin_id)
            @database = database
            @origin_id = origin_id
            @classifier = Retrieval::Evidence::Text
          end

          def index(intent_id, entries)
            entries.select { |entry| entry[:kind] == "file" }.each { |entry| index_file(intent_id, entry) }
          end

          private

          attr_reader :classifier, :database, :origin_id

          def writer = Retrieval::Evidence::Writer.new(database, origin_id)

          def index_file(intent_id, entry)
            path, data = entry.values_at(:path, :data)
            return unless classifier.classify(path, data) == :text

            writer.write(intent_id, path, data.dup.force_encoding(Encoding::UTF_8))
          end
        end
      end
    end
  end
end
