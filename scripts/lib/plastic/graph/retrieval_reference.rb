# frozen_string_literal: true

require "uri"

module Plastic
  module Graph
    # Resolves qualified document references within one retrieval store.
    class RetrievalReference
      def initialize(databases, store:, origin:)
        @databases = databases
        @store = store
        @origin = origin
      end

      def reference(intent_id, path)
        row = knowledge.row("SELECT h.sha256 FROM document_heads h WHERE h.intent_id = :intent_id AND h.path = :path AND h.origin_id = :origin", intent_id:, path:, origin: origin_id)
        raise RetrievalGraph::MissingReference, "no current document #{intent_id}:#{path}" unless row

        qualified(intent_id, path, row.fetch("sha256"))
      end

      def fetch(reference)
        fields = fields_for(reference)
        verify_store!(fields)
        row = document_row(fields)
        raise RetrievalGraph::MissingReference, "no document #{fields.fetch(:intent_id)}:#{fields.fetch(:path)}" unless row

        qualified(fields.fetch(:intent_id), fields.fetch(:path), row.fetch("sha256")).merge(body: row.fetch("body"))
      end

      def qualified_reference(intent_id, path, sha256) = qualified(intent_id, path, sha256)

      def fetch_passage(reference, position)
        document = fetch(reference)
        row = knowledge.row("SELECT body, line_start, line_end FROM document_passages WHERE intent_id = :intent_id AND path = :path AND sha256 = :sha256 AND position = :position AND origin_id = :origin",
          intent_id: document.fetch(:intent_id), path: document.fetch(:path), sha256: document.fetch(:revision), position:, origin: origin_id)
        raise RetrievalGraph::MissingReference, "no passage #{position}" unless row

        document.merge(position:, **row.transform_keys(&:to_sym))
      end

      private

      attr_reader :databases, :store, :origin

      def origin_id = origin.id

      def knowledge = databases.fetch(:knowledge)

      def fields_for(reference) = reference.is_a?(Hash) ? reference.transform_keys(&:to_sym) : parse(reference)

      def verify_store!(fields)
        return if fields.fetch(:store) == store

        raise RetrievalGraph::MissingReference, "source #{fields.fetch(:store)} is not #{store}"
      end

      def document_row(fields)
        revision = fields[:revision] || fields[:sha256]
        revision ? revision_row(fields, revision) : current_row(fields)
      end

      def qualified(intent_id, path, sha256)
        { store:, intent_id:, path:, revision: sha256, uri: "plastic://#{store}/#{intent_id}/#{escape_path(path)}?revision=#{sha256}" }
      end

      def parse(uri)
        match = /\Aplastic:\/\/([^\/]+)\/([^\/]+)\/([^?]*)(?:\?revision=([0-9a-f]{64}))?\z/.match(uri)
        raise RetrievalGraph::MissingReference, "invalid document reference #{uri.inspect}" unless match

        store_name, intent_id, path, sha256 = match.captures
        path = URI::DEFAULT_PARSER.unescape(path).force_encoding(Encoding::UTF_8)
        raise RetrievalGraph::MissingReference, "invalid document reference #{uri.inspect}" unless path.valid_encoding?

        { store: store_name, intent_id:, path:, revision: sha256 }
      end

      def escape_path(path) = path.bytes.map { |byte| unreserved?(byte) ? byte.chr : format("%%%02X", byte) }.join

      def unreserved?(byte) = byte.between?(65, 90) || byte.between?(97, 122) || byte.between?(48, 57) || "-._~".bytes.include?(byte)

      def revision_row(fields, sha256)
        knowledge.row("SELECT body, sha256 FROM document_revisions WHERE intent_id = :intent_id AND path = :path AND sha256 = :sha256 AND origin_id = :origin",
          intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), sha256:, origin: origin_id)
      end

      def current_row(fields)
        knowledge.row("SELECT d.body, h.sha256 FROM documents d JOIN document_heads h ON h.intent_id = d.intent_id AND h.path = d.path AND h.origin_id = d.origin_id WHERE d.intent_id = :intent_id AND d.path = :path AND d.origin_id = :origin",
          intent_id: fields.fetch(:intent_id), path: fields.fetch(:path), origin: origin_id)
      end
    end
  end
end
