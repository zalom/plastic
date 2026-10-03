# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Removes only mutable document views while preserving immutable revisions.
        class Removal
          def initialize(batch, origin_id)
            @batch = batch
            @origin_id = origin_id
          end

          def remove(intent_id, path)
            @batch.remove(:documents, intent_id:, path:)
            @batch.remove(:document_heads, intent_id:, path:)
            @batch.add("DELETE FROM document_fts WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin_id", intent_id:, path:, origin_id: @origin_id)
          end
        end
      end
    end
  end
end
