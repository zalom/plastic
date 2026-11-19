# frozen_string_literal: true

require_relative "integrity_records"
require_relative "integrity_sources"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Captures canonical evidence rows from knowledge and derived rows from retrieval for one origin.
        class IntegritySnapshot
          HEADS = ["document_heads", "intent_id, path, sha256"].freeze
          DERIVED = { passages: ["document_passages", "sha256, intent_id, path, position, body, line_start, line_end"], fts: ["document_fts", "intent_id, path, body, sha256, position"] }.freeze

          def initialize(store, origin_id, digester: Digest::SHA256)
            @store = store
            @origin_id = origin_id
            @digester = digester
          end

          def capture = capture_with(Evidence::IntegrityDatabaseSource.new(@store), derived)

          # The canonical rows through the transaction connection; the derived rows are not read, as no rebuild needs them.
          def capture_transaction(connection) = capture_with(Evidence::IntegrityTransactionSource.new(connection), {})

          private

          def derived
            return DERIVED.transform_values { [] } unless @store.retrieval_present?

            DERIVED.to_h { |name, (table, columns)| [name, select(Evidence::IntegrityDatabaseSource.new(@store), table, columns)] }
          end

          def capture_with(reader, derived)
            { heads: select(reader, *HEADS), documents: documents(reader), passages: [], fts: [] }.merge(derived)
          end

          def documents(reader) = select(reader, "documents", "intent_id, path, body, updated_at").map { |row| Evidence::IntegrityDocument.from_row(row, digester: @digester) }

          def select(reader, table, columns)
            reader.rows("SELECT #{columns} FROM #{table} WHERE origin_id = :origin", origin: @origin_id)
          end
        end
      end
    end
  end
end
