# frozen_string_literal: true

require "uri"

module Plastic
  module Graph
    module Retrieval
      # Parses and builds qualified references for one retrieval store.
      class Address
        UNRESERVED = "-._~".bytes.freeze

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
          TABLE = (0..255).map { |byte| ((65..90).cover?(byte) || (97..122).cover?(byte) || (48..57).cover?(byte) || UNRESERVED.include?(byte)) ? byte.chr : format("%%%02X", byte) }.freeze

          def initialize(path) = @bytes = path.bytes

          def encoded = @bytes.map { |byte| TABLE.fetch(byte) }.join
        end
      end
    end
  end
end
