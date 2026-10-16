# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Reads immutable document revisions and their passages from one origin.
      class DocumentReader
        def initialize(knowledge, origin_id)
          @knowledge = knowledge
          @origin_id = origin_id
        end

        def current_revision(intent_id, path)
          row = knowledge.row("SELECT h.sha256 FROM document_heads h WHERE h.intent_id = :intent_id AND h.path = :path AND h.origin_id = :origin", intent_id:, path:, origin: origin_id) ||
            raise(RetrievalGraph::MissingReference, "no current document #{intent_id}:#{path}")
          row.fetch("sha256")
        end

        def fetch(fields)
          document_row(fields) || raise(RetrievalGraph::MissingReference, "no document #{fields.fetch(:intent_id)}:#{fields.fetch(:path)}")
        end

        def passage(fields, position)
          row = knowledge.row("SELECT body, line_start, line_end FROM document_passages WHERE intent_id = :intent_id AND path = :path AND sha256 = :sha256 AND position = :position AND origin_id = :origin",
            intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), sha256: fields.fetch(:revision), position:, origin: origin_id) ||
            raise(RetrievalGraph::MissingReference, "no passage #{position}")
          row.transform_keys(&:to_sym)
        end

        private

        attr_reader :knowledge, :origin_id

        def document_row(fields)
          revision = fields[:revision] || fields[:sha256]
          revision ? revision_row(fields, revision) : current_row(fields)
        end

        def revision_row(fields, revision)
          knowledge.row("SELECT body, sha256 FROM document_revisions WHERE intent_id = :intent_id AND path = :path AND sha256 = :sha256 AND origin_id = :origin",
            intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), sha256: revision, origin: origin_id)
        end

        def current_row(fields)
          knowledge.row("SELECT d.body, h.sha256 FROM documents d JOIN document_heads h ON h.intent_id = d.intent_id AND h.path = d.path AND h.origin_id = d.origin_id WHERE d.intent_id = :intent_id AND d.path = :path AND d.origin_id = :origin",
            intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), origin: origin_id)
        end
      end
    end
  end
end
