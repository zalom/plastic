# frozen_string_literal: true

require "uri"

module Plastic
  module Graph
    # Parses and builds qualified references for one retrieval store.
    class RetrievalAddress
      def initialize(store) = @store = store

      def qualified(intent_id, path, revision)
        { store: @store, intent_id:, path:, revision:, uri: "plastic://#{@store}/#{intent_id}/#{escape(path)}?revision=#{revision}" }
      end

      def fields_for(reference)
        return reference.transform_keys(&:to_sym) if reference.is_a?(Hash)

        parse(reference)
      end

      def verify_store!(fields)
        return if fields.fetch(:store) == @store

        raise RetrievalGraph::MissingReference, "source #{fields.fetch(:store)} is not #{@store}"
      end

      private

      def parse(uri)
        match = /\Aplastic:\/\/([^\/]+)\/([^\/]+)\/([^?]*)(?:\?revision=([0-9a-f]{64}))?\z/.match(uri)
        invalid!(uri) unless match

        store, intent_id, path, revision = match.captures
        path = URI::DEFAULT_PARSER.unescape(path).force_encoding(Encoding::UTF_8)
        invalid!(uri) unless path.valid_encoding?

        { store:, intent_id:, path:, revision: }
      end

      def invalid!(uri) = raise RetrievalGraph::MissingReference, "invalid document reference #{uri.inspect}"

      def escape(path) = path.bytes.map { |byte| unreserved?(byte) ? byte.chr : format("%%%02X", byte) }.join

      def unreserved?(byte) = byte.between?(65, 90) || byte.between?(97, 122) || byte.between?(48, 57) || "-._~".bytes.include?(byte)
    end
  end
end
