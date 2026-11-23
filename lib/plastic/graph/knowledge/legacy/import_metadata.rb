# frozen_string_literal: true

require_relative "check"
require_relative "metadata_rows"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The checked read of a legacy store and the metadata rows written from it.
        class ImportMetadata
          # What the legacy store held before the import wrote any row.
          Read = Data.define(:originals, :decisions)

          def initialize(folder, retrieval, home)
            @folder = folder
            @retrieval = retrieval
            @home = home
          end

          def store = @retrieval.store

          def call(&reader)
            Check.new(@folder).call
            import(&reader)
          end

          private

          def import
            @folder.ignore_databases
            read = legacy_read
            lines = yield
            [lines, written(read)]
          end

          def legacy_read(parsed)
            originals = @folder.intent_files.to_h { |path| [path, @folder.read(path)] }
            Read.new(originals, Decisions.read(@folder.intent_dirs, originals))
          end

          def opened = Graph.open(home: @home, store:)

          def written(read)
            graphs = opened
            tally.tap { |counts| MetadataRows.new(graphs, @folder, counts).call(read) }
          end

          def tally = Hash.new(0).merge(intents: @retrieval.intents.size, documents: @retrieval.documents.size,
            legacy_intents_data: @retrieval.stored.legacy_intents_data.size, work_log: @retrieval.structure.work_log.size)
        end
      end
    end
  end
end
