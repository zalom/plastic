# frozen_string_literal: true

require "uri"

module Plastic
  module Graph
    # Parses and builds qualified references for one retrieval store.
    class RetrievalAddress
      def initialize(store) = @store = store

      def qualified(intent_id, path, revision)
        { store: @store, intent_id:, path:, revision:, uri: "plastic://#{@store}/#{intent_id}/#{PathEscaper.new(path).encoded}?revision=#{revision}" }
      end

      def fields_for(reference) = ReferenceFields.new(reference, method(:parse)).fields

      def verify_store(fields)
        source = fields.fetch(:store)
        return if source == @store

        raise RetrievalGraph::MissingReference, "source #{source} is not #{@store}"
      end

      private

      def parse(uri)
        store, intent_id, encoded_path, revision = captures(uri)
        { store:, intent_id:, path: decode_path(uri, encoded_path), revision: }
      end

      def captures(uri) = reference_match(uri).captures

      def reference_match(uri)
        /\Aplastic:\/\/([^\/]+)\/([^\/]+)\/([^?]*)(?:\?revision=([0-9a-f]{64}))?\z/.match(uri) || invalid(uri)
      end

      def decode_path(uri, encoded_path)
        path = URI::DEFAULT_PARSER.unescape(encoded_path).force_encoding(Encoding::UTF_8)
        path.valid_encoding? ? path : invalid(uri)
      end

      def invalid(uri) = raise RetrievalGraph::MissingReference, "invalid document reference #{uri.inspect}"

      # Converts either an already parsed reference or a qualified URI to fields.
      class ReferenceFields
        def initialize(reference, parser)
          @reference = reference
          @parser = parser
        end

        def fields = @reference.is_a?(Hash) ? @reference.transform_keys(&:to_sym) : @parser.call(@reference)
      end

      # Escapes a document path for its qualified retrieval URI.
      class PathEscaper
        def initialize(path)
          @bytes = path.bytes
          @unreserved = "-._~".bytes
        end

        def encoded = @bytes.map { |byte| literal?(byte) ? byte.chr : format("%%%02X", byte) }.join

        private

        def literal?(byte)
          byte.between?(65, 90) || byte.between?(97, 122) || byte.between?(48, 57) || @unreserved.include?(byte)
        end
      end
    end
  end
end
