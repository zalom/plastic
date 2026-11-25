# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Removes one document and its head.
        class Removal
          def initialize(batch, origin_id)
            @batch = batch
            @origin_id = origin_id
          end

          def remove(intent_id, path)
            @batch.remove(:documents, intent_id:, path:)
            @batch.remove(:document_heads, intent_id:, path:)
          end
        end
      end
    end
  end
end
