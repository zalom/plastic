# frozen_string_literal: true

require_relative "document"
require_relative "rows"
require_relative "removal"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Writes one immutable text revision and its current head. The passages and search entries are built apart.
        class Writer
          attr_reader :origin_id

          def initialize(database, origin_id, clock:)
            @database = database
            @origin_id = origin_id
            @clock = clock
          end

          def write(intent_id, path, body)
            document = Evidence::Document.new(intent_id, path, body, now: Plastic.timestamp(@clock.now))
            @database.transaction { |batch| apply_document(batch, document) }
          end

          def apply(batch, intent_id, path, body)
            document = Evidence::Document.new(intent_id, path, body, now: Plastic.timestamp(@clock.now))
            apply_document(batch, document)
          end

          def remove(intent_id, path)
            @database.transaction { |batch| Evidence::Removal.new(batch, @origin_id).remove(intent_id, path) }
          end

          private

          def apply_document(batch, document)
            Evidence::Rows.new(batch, document, @origin_id).write
          end
        end
      end
    end
  end
end
