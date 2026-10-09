# frozen_string_literal: true

require_relative "../intent"
require_relative "../legacy/index"
require_relative "../../prints"
require_relative "../../schema"
require_relative "../store_folder"
require_relative "../legacy/store_import"

module Plastic
  module Graph
    module Knowledge
      class Graph::Knowledge::Sync
        # The full first sync delegates preservation and metadata to Graph::Knowledge::Legacy::StoreImport.
        # Its read_rows primitive reads intents, clusters and ordinary files, then
        # prints the store. graph.json remains a generated view and is never imported.
        class LegacyImport
          FRONT_MATTER = /\A---\n(.*?)\n---/m
          FIELD = /^(\w+):[ \t]*"?([^"\n]*?)"?[ \t]*$/

          def initialize(sync, folder, retrieval, databases)
            @sync = sync
            @folder = folder
            @retrieval = retrieval
            @databases = databases
          end

          def call = Legacy::StoreImport.new(self, @folder, @retrieval, @databases).call

          def read_rows
            parsed = write_index
            read = @sync.read(@folder.intent_files.reject { |path| Graph::Knowledge::StoreFolder.graph_view?(path) })
            finish
            ["imported #{Graph::Knowledge::StoreFolder::LEGACY_INDEX}: #{Schema.phrase(parsed.counts)}", *read]
          end

          private

          def write_index
            Legacy::Index.parse(@folder.read(Graph::Knowledge::StoreFolder::LEGACY_INDEX).force_encoding(Encoding::UTF_8)).tap do |parsed|
              write(parsed.check(@folder.intent_dirs))
            end
          end

          def write(parsed)
            now = Plastic.now
            rows = parsed.entries.map { |entry| entry.row(front_matter(entry.dir), now) }
            @databases.fetch(:work).transaction do |batch|
              batch.put_all(:intents, rows).put_all(:clusters, parsed.clusters.map(&:to_h))
            end
          end

          def finish
            @sync.printer.print(Prints.of_store(@retrieval))
          end

          # The fields at the head of the intent's own file.
          def front_matter(dir)
            file = @folder.own_file(dir)
            text = @folder.exist?(file) ? @folder.read(file).force_encoding(Encoding::UTF_8) : ""
            text[FRONT_MATTER, 1].to_s.scan(FIELD).to_h
          end
        end
      end
    end
  end
end
