# frozen_string_literal: true

require_relative "../intent"
require_relative "../legacy_index"
require_relative "../prints"
require_relative "../store_folder"

module Plastic
  module Graph
    class Sync
      # The first sync up of a store written before store/index.json: reads
      # INDEX.md into intent and cluster rows, every file of every intent
      # folder into rows, prints the whole store, and deletes INDEX.md.
      class LegacyImport
        FRONT_MATTER = /\A---\n(.*?)\n---/m
        FIELD = /^(\w+):[ \t]*"?([^"\n]*?)"?[ \t]*$/

        def initialize(sync, folder, retrieval, databases)
          @sync = sync
          @folder = folder
          @retrieval = retrieval
          @databases = databases
        end

        def call
          parsed = LegacyIndex.parse(@folder.read(StoreFolder::LEGACY_INDEX).force_encoding(Encoding::UTF_8))
          parsed.check(@folder.intent_dirs)
          write(parsed)
          read = @sync.read(@folder.intent_files)
          @sync.printer.print(Prints.of_store(@retrieval))
          @folder.delete(StoreFolder::LEGACY_INDEX)
          ["imported #{StoreFolder::LEGACY_INDEX}: #{counted(parsed)}, then deleted it", *read]
        end

        private

        def write(parsed)
          now = Plastic.now
          @databases.fetch(:work).transaction do |batch|
            parsed.entries.each { |entry| batch.put(:intents, row(entry, now)) }
            parsed.clusters.each { |member| batch.put(:clusters, member.to_h) }
          end
        end

        def row(entry, now)
          front = front_matter(entry.dir)
          { intent_id: entry.intent_id, parent_id: Intent.parent_of(entry.intent_id),
            slug: File.basename(entry.dir).split("--", 2).last, title: entry.title, kind: front["kind"],
            status: entry.status, disposition: entry.disposition, opened_at: front["created"],
            closed_at: entry.closed_at, updated_at: now }
        end

        # The fields at the head of the intent's own file.
        def front_matter(dir)
          file = "#{dir}/#{File.basename(dir)}.md"
          text = @folder.exist?(file) ? @folder.read(file).force_encoding(Encoding::UTF_8) : ""
          text[FRONT_MATTER, 1].to_s.scan(FIELD).to_h
        end

        def counted(parsed) = Schema.phrase({ "intents" => parsed.entries.size, "clusters" => parsed.clusters.size })
      end
    end
  end
end
