# frozen_string_literal: true

require_relative "evidence/writer"
require_relative "evidence/text"

module Plastic
  module Graph
    module Retrieval
      # Imports eligible legacy attachments after the retrieval schema appears.
      class ReferenceBackfill
        SCHEMA_VERSION = 1

        def self.complete?(path, origin_id)
          return false unless File.file?(path)

          database = Database::ConnectionPool.for(path)
          tables = database.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'retrieval_backfills'")
          tables.any? && database.execute(complete_sql, [origin_id, SCHEMA_VERSION]).any?
        rescue SQLite3::Exception, SystemCallError
          false
        end

        def initialize(databases, origin_id, after_write: -> {})
          @knowledge = databases.fetch(:knowledge)
          @references = databases.fetch(:references)
          @origin_id = origin_id
          @after_write = after_write
        end

        def call
          return self if complete?

          scan { |document| write_missing(document) }
          mark_complete
          self
        end

        def self.complete_sql
          "SELECT 1 FROM retrieval_backfills WHERE name = 'retrieval' AND origin_id = ? AND version >= ?"
        end

        private

        def scan
          legacy_documents.each { |row| yield LegacyDocument.from_document(row) }
          legacy_references.each { |row| yield LegacyDocument.from_reference(row) }
        end

        def legacy_references
          @references.rows("SELECT name, data, intent_id FROM sqlar WHERE origin_id = :origin", origin: @origin_id)
            .select { |row| Evidence::Text.classify(row.fetch("name"), row.fetch("data")) == :text }
        end

        def legacy_documents
          @knowledge.rows("SELECT intent_id, path, body FROM documents WHERE origin_id = :origin", origin: @origin_id)
        end

        def write_missing(document)
          intent_id, path, body = document.deconstruct
          return if head_exists?(intent_id, path)

          Evidence::Writer.new(@knowledge, @origin_id).write(intent_id, path, body)
          @after_write.call
        end

        def head_exists?(intent_id, path)
          @knowledge.row("SELECT 1 FROM document_heads WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin",
            intent_id:, path:, origin: @origin_id)
        end

        def complete?
          @knowledge.row("SELECT 1 FROM retrieval_backfills WHERE name = 'retrieval' AND origin_id = :origin AND version >= :version",
            origin: @origin_id, version: SCHEMA_VERSION)
        end

        def mark_complete
          @knowledge.transaction do |batch|
            batch.add("INSERT INTO retrieval_backfills (name, origin_id, version, completed_at) VALUES ('retrieval', :origin, :version, :completed_at) ON CONFLICT(name, origin_id) DO UPDATE SET version = MAX(version, excluded.version), completed_at = excluded.completed_at",
              origin: @origin_id, version: SCHEMA_VERSION, completed_at: Plastic.now)
            batch.add("UPDATE retrieval_schema SET completed_at = 'complete' WHERE name = 'retrieval'")
          end
        end

        # Holds one immutable legacy document before it enters the evidence writer.
        LegacyDocument = Data.define(:intent_id, :path, :body) do
          def self.from_document(row)
            new(row.fetch("intent_id"), row.fetch("path"), row.fetch("body"))
          end

          def self.from_reference(row)
            new(row.fetch("intent_id"), row.fetch("name").split("/", 3).last, row.fetch("data").dup.force_encoding(Encoding::UTF_8))
          end
        end
      end
    end
  end
end
