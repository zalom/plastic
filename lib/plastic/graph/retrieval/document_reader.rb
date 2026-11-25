# frozen_string_literal: true

require_relative "errors"

module Plastic
  module Graph
    module Retrieval
      # Reads the current text of each document, and its passages, from one origin. A pinned reference reads back
      # only while it names the current text.
      class DocumentReader
        def initialize(store, origin_id)
          @store = store
          @origin_id = origin_id
        end

        def current_revision(intent_id, path)
          row = store.row("SELECT h.sha256 FROM document_heads h WHERE h.intent_id = :intent_id AND h.path = :path AND h.origin_id = :origin", intent_id:, path:, origin: origin_id) ||
            raise(RetrievalGraph::MissingReference, "no current document #{intent_id}:#{path}")
          row.fetch("sha256")
        end

        def fetch(fields)
          document_row(fields) || raise(RetrievalGraph::MissingReference, "no document #{fields.fetch(:intent_id)}:#{fields.fetch(:path)}")
        end

        def passage(fields, position)
          row = retrieval_rows("SELECT body, line_start, line_end FROM document_passages WHERE intent_id = :intent_id AND path = :path AND sha256 = :sha256 AND position = :position AND origin_id = :origin",
            intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), sha256: fields.fetch(:revision), position:, origin: origin_id) ||
            raise(RetrievalGraph::MissingReference, "no passage #{position}")
          row.transform_keys(&:to_sym)
        end

        private

        attr_reader :store, :origin_id

        def retrieval_rows(sql, **values)
          raise RetrievalGraph::MaintenanceRequired, Search::MISSING unless store.retrieval_present?

          store.row(sql, **values)
        end

        def document_row(fields)
          revision = fields[:revision] || fields[:sha256]
          row = current_row(fields)
          row if row && (revision.nil? || row.fetch("sha256") == revision)
        end

        def current_row(fields)
          store.row("SELECT d.body, h.sha256 FROM documents d JOIN document_heads h ON h.intent_id = d.intent_id AND h.path = d.path AND h.origin_id = d.origin_id WHERE d.intent_id = :intent_id AND d.path = :path AND d.origin_id = :origin",
            intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), origin: origin_id)
        end
      end
    end
  end
end
