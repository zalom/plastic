# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Writes the evidence rows in dependency order: the document, then its head.
        class Rows
          def initialize(batch, document, origin_id)
            @batch = batch
            @document = document
            @origin_id = origin_id
          end

          def write
            @batch.put(:documents, @document.document_row)
            current_rows
          end

          private

          def current_rows = @batch.put(:document_heads, @document.head_row)
        end
      end
    end
  end
end
