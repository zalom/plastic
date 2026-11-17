# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The one database of a store: knowledge is the main file, work and retrieval are attached to it, and every table
      # name is unique across the three, so a statement names no schema. A write runs in BEGIN IMMEDIATE, which reserves
      # all three files, so rows of work and knowledge land together or not at all.
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
          super(File.join(root, Schema.file(:knowledge)), nil, origin:, track: { sequence: :store, key: :knowledge })
          @files = Store.attachments(path)
        end

        def retrieval_path = files.fetch(:retrieval)

        # False when the knowledge file was there and the retrieval file was not when the connection opened, until a rebuild writes it again. ATTACH makes a file for a missing one.
        def retrieval_present?
          open_file
          !@retrieval_lost
        end

        # What this call wrote, as the report says it, one phrase for each file in the order work, knowledge, retrieval.
        def phrases
          counted = written.except(RUNS).group_by { |table, _count| Schema.file_of(table) }
          FILES.filter_map { |file| "#{Schema.phrase(counted.fetch(file).to_h)} in #{file}" if counted.key?(file) }
        end

        # Runs a search rebuild in a deferred transaction, which takes the write lock of a file only when it first writes
        # there. The rebuild reads before it and writes only retrieval tables, so work and knowledge stay writable.
        def rebuilding
          batch = Batch.new(origin: @origin)
          connected do |connection|
            connection.deferred do
              yield batch, connection
              write(connection, batch) unless batch.empty?
            end
          end.tap { @retrieval_lost = false }
        end

        private

        def open_file
          refuse_behind unless ConnectionPool.connections.key?(path)
          ConnectionPool.for(path, attach: files)
        end

        # ATTACH makes a file for a missing one, so a store that is behind and lacks an attached file is refused before the first ATTACH.
        def refuse_behind
          @retrieval_lost = File.file?(path) && !File.file?(retrieval_path)
          raise Behind, "#{file} is behind this code; run plastic update" if files.values.any? { |attached| !File.file?(attached) } && SchemaGate.behind?(path, files.values)
        end

        def settle(connection)
          SchemaGate.new(connection, layouts: SCHEMAS.invert, file:).call
        end
      end
    end
  end
end
