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
        class LegacyImport
          def initialize(sync, folder, retrieval, databases, rollback: Legacy::ImportRollback)
            @rollback = rollback
            @sync = sync
            @folder = folder
            @retrieval = retrieval
            @databases = databases
          end

          def call = Legacy::StoreImport.new(self, @folder, @retrieval, @databases, rollback: @rollback).call

          def read_rows
            parsed = write_index
            read = intents_read
            finish
            ["imported #{Graph::Knowledge::StoreFolder::LEGACY_INDEX}: #{Schema.phrase(parsed.counts)}", *read]
          end

          private

          def write_index
            listed = Legacy::Index.parse(@folder.read(Graph::Knowledge::StoreFolder::LEGACY_INDEX).force_encoding(Encoding::UTF_8))
            Legacy::Index::Parsed.new(listed.entries + unlisted(listed), listed.clusters).tap { |parsed| write(parsed) }
          end

          def unlisted(listed)
            (@folder.intent_dirs - listed.entries.map(&:dir)).map do |dir|
              front = @folder.front_matter(dir)
              Legacy::Index::Entry.new(File.basename(dir).split("--", 2).first, front["intent"], dir, front["status"], nil, nil)
            end
          end

          def write(parsed)
            now = Plastic.now
            rows = parsed.entries.map { |entry| entry.row(@folder.front_matter(entry.dir), now) }
            @databases.fetch(:work).transaction do |batch|
              batch.put_all(:intents, rows).put_all(:clusters, parsed.clusters.map(&:to_h))
            end
          end

          def intents_read
            dirs = @folder.intent_dirs
            dirs.each_with_index.flat_map do |dir, index|
              paths = @folder.files(dir).reject { |path| Graph::Knowledge::StoreFolder.context_view?(path) }
              [*@sync.read(paths), "imported intent #{index + 1} of #{dirs.size}: #{File.basename(dir).split("--", 2).first}"]
            end
          end

          def finish
            @sync.printer.print(Prints.of_store(@retrieval))
          end
        end
      end
    end
  end
end
