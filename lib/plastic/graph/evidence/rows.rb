# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Writes canonical, immutable, and current evidence rows in dependency order: the revision, then the head.
        class Rows
          def initialize(batch, document, origin_id)
            @batch = batch
            @document = document
            @origin_id = origin_id
          end

          def write
            @batch.put(:documents, @document.document_row)
            immutable_rows
            current_rows
          end

          private

          def immutable_rows
            @batch.add("INSERT OR IGNORE INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id) VALUES (:sha256, :intent_id, :path, :body, :created_at, :origin_id)", **@document.revision_row(@origin_id))
          end

          def current_rows = @batch.put(:document_heads, @document.head_row)
        end
      end
    end
  end
end
