# frozen_string_literal: true

require_relative "../../evidence/text"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Rebuilds the document heads from verified immutable evidence.
        class IntegrityRebuilder
          def initialize(origin_id) = @origin_id = origin_id

          def rebuild(batch, snapshot)
            clear(batch)
            snapshot.fetch(:documents).each { |document| rebuild_current(batch, document) }
          end

          private

          def clear(batch)
            batch.add("DELETE FROM document_heads WHERE origin_id = :origin", origin: @origin_id)
          end

          def rebuild_current(batch, document)
            batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (:intent_id, :path, :sha256, :updated_at, :origin_id)", **document.head_row(@origin_id))
          end
        end
      end
    end
  end
end
