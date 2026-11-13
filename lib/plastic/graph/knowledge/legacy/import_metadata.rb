# frozen_string_literal: true

require_relative "check"
require_relative "roadmaps"
require_relative "metadata_rows"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The checked read of a legacy store and the metadata rows written from it.
        class ImportMetadata
          # What the legacy store held before the import wrote any row.
          Read = Data.define(:parsed, :originals, :decisions)

          def initialize(folder, retrieval, home)
            @folder = folder
            @retrieval = retrieval
            @home = home
          end

          def store = @retrieval.store

          def call(&reader)
            Check.new(@folder).call
            import(Roadmaps.new(@folder.root).parse, &reader)
          end

          private

          def import(parsed)
            @folder.ignore_databases
            read = legacy_read(parsed)
            lines = yield
            [lines, written(read)]
          end

          def legacy_read(parsed)
            originals = @folder.intent_files.to_h { |path| [path, @folder.read(path)] }
            Read.new(parsed, originals, Decisions.new.read_decisions(@folder.intent_dirs, originals))
          end

          def opened = Graph.open(home: @home, store:)

          def written(read)
            graphs = opened
            tally.tap { |counts| MetadataRows.new(graphs, @folder, counts).call(read) }
          end

          def tally = Hash.new(0).merge(intents: @retrieval.intents.size, documents: @retrieval.documents.size,
            legacy_intents_data: @retrieval.legacy_intents_data.size, savepoints: @retrieval.savepoints.size)
        end
      end
    end
  end
end
