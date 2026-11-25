# frozen_string_literal: true

require "digest"
require_relative "../../evidence/text"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # A current document that supplies its head, passage and FTS rows.
        IntegrityDocument = Data.define(:intent_id, :path, :body, :updated_at, :digest) do
          def self.from_row(row, digester: Digest::SHA256) = new(**row.transform_keys(&:to_sym), digest: digester.hexdigest(row.fetch("body")))
          def passages = Evidence::Text.passages(Evidence::Text.extract_with_lines(path, body))
          def head_values = [intent_id, path, digest]
          def passage_values = passages.map { |passage| [digest, intent_id, path, *passage.values_at(:position, :body, :line_start, :line_end)] }
          def passage_rows(origin_id) = passages.map { |passage| { sha256: digest, intent_id:, path:, origin_id:, **passage } }
          def head_row(origin_id) = { intent_id:, path:, sha256: digest, updated_at:, origin_id: }
          def fts_rows(origin_id) = passages.map { |passage| { body: passage.fetch(:body), intent_id:, path:, sha256: digest, position: passage.fetch(:position), origin_id: } }
        end
      end
    end
  end
end
