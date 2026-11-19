# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The one database of a store: knowledge is the main file, work and retrieval are attached to it, and every table
      # name is unique across the three, so a statement names no schema. A write runs in BEGIN IMMEDIATE, which reserves
      # all three files, so rows of work and knowledge land together or not at all. Each write gives the pages it freed back
      # to the disk before it commits.
      class Store < Database
        SCHEMAS = { knowledge: "main", work: "work", retrieval: "retrieval" }.freeze
        FILES = [*Schema.store, *Schema.derived].map { |key| Schema.file(key) }.freeze

        # The files attached to the knowledge file `path`, by schema name.
        def self.attachments(path)
          folder = File.dirname(path)
          { work: File.join(folder, Schema.file(:work)), retrieval: File.join(folder, Schema.file(:retrieval)) }
        end

        attr_reader :files

        def initialize(root, origin)
          super(File.join(root, Schema.file(:knowledge)), nil, origin:, key: :knowledge, layouts: SCHEMAS.invert)
          @files = Store.attachments(path)
          @retrieval_lost = false
        end

        def retrieval_path = files.fetch(:retrieval)

        # False when the knowledge file was there and the retrieval file was not when the connection opened, until a rebuild writes it again. ATTACH makes a file for a missing one.
        def retrieval_present?
          open_file
          !@retrieval_lost
        end

        # What this call wrote, as the report says it, one phrase for each file in the order work, knowledge, retrieval.
        def phrases = written_by_file.sort_by { |file, _tables| FILES.index(file) }.map { |file, tables| "#{Schema.phrase(tables)} in #{file}" }

        # Runs a search rebuild in a deferred transaction, which takes the write lock of a file only when it first writes
        # there. The rebuild reads before it and writes only retrieval tables, and gives back free pages of retrieval only,
        # so work and knowledge stay writable.
        def rebuilding
          batch = Batch.new(origin:)
          connected do |connection|
            connection.deferred do
              yield batch, connection
              write(connection, batch, schemas: %w[retrieval]) unless batch.empty?
            end
          end.tap { @retrieval_lost = false }
        end

        private

        def write(connection, batch, schemas: SCHEMAS.values)
          super(connection, batch).tap { schemas.each { |schema| connection.give_back_free_pages(schema) } }
        end

        def written_by_file = written.except(RUNS).group_by { |table, _count| Schema.file_of(table) }.transform_values(&:to_h)

        def open_file
          refuse_behind unless ConnectionPool.connections.key?(path)
          ConnectionPool.for(path, attach: files)
        end

        # ATTACH makes a file for a missing one, so a store that is behind and lacks an attached file is refused before the first ATTACH.
        def refuse_behind
          @retrieval_lost = File.file?(path) && !File.file?(retrieval_path)
          attached = files.values
          raise Behind, "#{file} is behind this code; run plastic update" if attached.any? { |attachment| !File.file?(attachment) } && SchemaGate.behind?(path, attached)
        end
      end
    end
  end
end
