# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Writes canonical, immutable, and current evidence rows in dependency order.
        class Rows
          def initialize(batch, document, origin_id)
            @batch = batch
            @document = document
            @origin_id = origin_id
          end

          def write
            @batch.put(:documents, @document.document_row)
            immutable_rows
            yield
            current_rows
          end

          private

          def immutable_rows
            @batch.add("INSERT OR IGNORE INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id) VALUES (:sha256, :intent_id, :path, :body, :created_at, :origin_id)", **@document.revision_row(@origin_id))
            @document.passages.each { |passage| immutable_passage(passage) }
          end

          def immutable_passage(passage)
            @batch.add("INSERT OR IGNORE INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES (:sha256, :intent_id, :path, :position, :body, :line_start, :line_end, :origin_id)", sha256: @document.revision, intent_id: @document.intent_id, path: @document.path, origin_id: @origin_id, **passage)
          end

          def current_rows
            @batch.put(:document_heads, @document.head_row)
            @batch.add("DELETE FROM document_fts WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin_id", intent_id: @document.intent_id, path: @document.path, origin_id: @origin_id)
            @document.passages.each { |passage| current_passage(passage) }
          end

          def current_passage(passage)
            @batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)", body: passage.fetch(:body), intent_id: @document.intent_id, path: @document.path, sha256: @document.revision, position: passage.fetch(:position), origin_id: @origin_id)
          end
        end
      end
    end
  end
end
