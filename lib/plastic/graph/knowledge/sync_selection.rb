# frozen_string_literal: true

require_relative "legacy_path"
require_relative "reports"
require_relative "../../layout"

module Plastic
  module Graph
    module Knowledge
      # Which files of an intent folder a sync reads into rows. The notes in the
      # intent root, the graph, the context and the legacy action files are
      # always read. Under resources/, the output folders are read by file type,
      # a file of output/reports/ only when it is a recorded or a mandatory
      # report of its intent, references/ only when its setting is on, and tmp/
      # never. `rel` is the path inside the intent folder.
      class SyncSelection
        REFERENCES = Layout.resource(:references)
        OUTPUT = Layout.output_folders
        INTENT_FILE = %r{\Astore/(?<intent_id>[^/]*?)--[^/]*/(?<rel>.+)\z}

        def self.none = new(types: [], references: false, asked: [])

        # The intent id of an intent folder of the store, as store/7--title gives 7.
        def self.intent_of(dir) = dir[%r{\Astore/([^/]*?)--}, 1]

        def self.output?(rel) = OUTPUT.any? { |folder| rel.start_with?(folder) }

        def self.note?(rel) = Layout.read?(rel)

        def self.type_of(rel) = File.extname(rel).delete_prefix(".").downcase

        attr_reader :reports

        def initialize(types:, references:, asked:, reports: Reports.none)
          @types = types
          @references = references
          @asked = asked
          @reports = reports
        end

        # The same selection, with the recorded reports read from the store `database`.
        def for_store(database) = SyncSelection.new(types: @types, references: @references, asked: @asked, reports: @reports.recorded_from(database))

        def read?(rel, intent_id: nil)
          return true if SyncSelection.note?(rel)
          return @references if rel.start_with?(REFERENCES)
          return false unless reads_type?(rel)

          !Reports.report?(rel) || @reports.listed?(intent_id, rel)
        end

        # Whether `rel` is a file of an output folder whose type the sync reads.
        def reads_type?(rel) = SyncSelection.output?(rel) && @types.include?(SyncSelection.type_of(rel))

        def selects?(path)
          match = INTENT_FILE.match(path)
          match.nil? || read?(match[:rel], intent_id: match[:intent_id])
        end

        def new_types(rels)
          rels.select { |rel| SyncSelection.output?(rel) }.map { |rel| SyncSelection.type_of(rel) }.uniq - @types - @asked - [""]
        end
      end
    end
  end
end
