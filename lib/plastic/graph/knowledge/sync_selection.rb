# frozen_string_literal: true

require_relative "legacy_path"

module Plastic
  module Graph
    module Knowledge
      # Which files of an intent folder a sync reads into rows. The notes in the
      # intent root, the graph, the context and the legacy action files are
      # always read. Under resources/, the output folders are read by file type,
      # references/ only when its setting is on, and tmp/ never. `rel` is the
      # path inside the intent folder.
      class SyncSelection
        NOTES = %w[graph.json context.json work.log].freeze
        REFERENCES = "resources/references/"
        OUTPUT = %w[resources/output/reports/ resources/output/files/].freeze
        INTENT_FILE = %r{\Astore/[^/]*--[^/]*/(.+)\z}

        def self.none = new(types: [], references: false, asked: [])

        # The selection the `settings` name, as a Config reads them.
        def self.of(settings)
          new(types: settings.list("sync.types"), references: settings.flag(%w[sync references], default: false), asked: settings.list("sync.asked"))
        end

        def self.output?(rel) = OUTPUT.any? { |folder| rel.start_with?(folder) }

        def self.root_note?(rel) = !rel.include?("/") && type_of(rel) == "md"

        def self.note?(rel) = root_note?(rel) || NOTES.include?(rel) || LegacyPath.legacy?(rel)

        def self.type_of(rel) = File.extname(rel).delete_prefix(".").downcase

        def initialize(types:, references:, asked:)
          @types = types
          @references = references
          @asked = asked
        end

        def read?(rel)
          return true if SyncSelection.note?(rel)
          return @references if rel.start_with?(REFERENCES)

          SyncSelection.output?(rel) && @types.include?(SyncSelection.type_of(rel))
        end

        def selects?(path)
          rel = path[INTENT_FILE, 1]
          rel.nil? || read?(rel)
        end

        def new_types(rels)
          rels.select { |rel| SyncSelection.output?(rel) }.map { |rel| SyncSelection.type_of(rel) }.uniq - @types - @asked - [""]
        end
      end
    end
  end
end
