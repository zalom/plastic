# frozen_string_literal: true

require_relative "text"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Rebuilds derived search rows from verified immutable evidence.
        class IntegrityRebuilder
          def initialize(origin_id) = @origin_id = origin_id

          def rebuild(batch, snapshot)
            clear(batch)
            snapshot.fetch(:revisions).each { |revision| rebuild_passages(batch, revision) }
            snapshot.fetch(:documents).each { |document| rebuild_current(batch, document) }
          end

          private

          def clear(batch)
            %w[document_heads document_passages document_fts].each { |table| batch.add("DELETE FROM #{table} WHERE origin_id = :origin", origin: @origin_id) }
          end

          def rebuild_passages(batch, revision)
            revision.passage_rows(@origin_id).each do |row|
              batch.add("INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES (:sha256, :intent_id, :path, :position, :body, :line_start, :line_end, :origin_id)", **row)
            end
          end

          def rebuild_current(batch, document)
            batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (:intent_id, :path, :sha256, :updated_at, :origin_id)", **document.head_row(@origin_id))
            document.fts_rows(@origin_id).each do |row|
              batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES (:body, :intent_id, :path, :sha256, :position, :origin_id)", **row)
            end
          end
        end
      end
    end
  end
end
