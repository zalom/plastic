# frozen_string_literal: true

require_relative "../intent"
require_relative "../legacy_index"
require_relative "../prints"
require_relative "../schema"
require_relative "../store_folder"
require_relative "../legacy_store_import"

module Plastic
  module Graph
    class Sync
      # The first sync up of a store written before store/index.json: reads
      # INDEX.md into intent and cluster rows, every file of every intent
      # folder into rows, and prints the whole store. INDEX.md stays: migrate
      # stores removes it only after the whole store imports, and only when
      # migrate.remove_after_import is on in config.yml.
      class LegacyImport
        FRONT_MATTER = /\A---\n(.*?)\n---/m
        FIELD = /^(\w+):[ \t]*"?([^"\n]*?)"?[ \t]*$/

        def initialize(sync, folder, retrieval, databases)
          @sync = sync
          @folder = folder
          @retrieval = retrieval
          @databases = databases
        end

        def call = LegacyStoreImport.new(self, @folder, @retrieval, @databases).call

        def read_rows
          parsed = LegacyIndex.parse(@folder.read(StoreFolder::LEGACY_INDEX).force_encoding(Encoding::UTF_8))
          write(parsed.check(@folder.intent_dirs))
          read = @sync.read(@folder.intent_files)
          finish
          ["imported #{StoreFolder::LEGACY_INDEX}: #{Schema.phrase(parsed.counts)}", *read]
        end

        private

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
          file = "#{dir}/#{File.basename(dir)}.md"
          text = @folder.exist?(file) ? @folder.read(file).force_encoding(Encoding::UTF_8) : ""
          text[FRONT_MATTER, 1].to_s.scan(FIELD).to_h
        end
      end
    end
  end
end
