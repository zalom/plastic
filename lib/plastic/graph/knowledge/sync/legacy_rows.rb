# frozen_string_literal: true

require_relative "../intent"
require_relative "../legacy/index"
require_relative "../../prints"
require_relative "../../schema"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Graph::Knowledge::Sync
        # Reads the legacy index and the intent files of a store into rows, and prints the rows back.
        class LegacyRows
          def initialize(sync, folder, retrieval, databases)
            @sync = sync
            @folder = folder
            @retrieval = retrieval
            @databases = databases
          end

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
              front = FrontMatter.new(@folder).read(dir)
              Legacy::Index::Entry.new(File.basename(dir).split("--", 2).first, front["intent"], dir, front["status"], nil, nil)
            end
          end

          def write(parsed)
            now = Plastic.now
            rows = parsed.entries.map { |entry| entry.row(FrontMatter.new(@folder).read(entry.dir), now) }
            @databases.fetch(:work).transaction do |batch|
              batch.put_all(:intents, rows).put_all(:clusters, parsed.clusters.map(&:to_h))
            end
          end

          def intents_read
            dirs = @folder.intent_dirs
            dirs.each_with_index.flat_map { |dir, index| [*@sync.read(readable_paths(dir)), "imported intent #{index + 1} of #{dirs.size}: #{File.basename(dir).split("--", 2).first}"] }
          end

          def readable_paths(dir) = @folder.files(dir).reject { |path| Graph::Knowledge::StoreFolder.context_view?(path) }

          def finish
            @sync.printer.print(Prints.of_store(@retrieval))
          end
        end
      end
    end
  end
end
