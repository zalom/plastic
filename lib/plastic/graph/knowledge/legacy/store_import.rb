# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "check"
require_relative "decisions"
require_relative "roadmaps"
require_relative "originals"
require_relative "import_rollback"
require_relative "import_cleanup"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The complete first sync of one legacy store, with rollback and preserved originals.
        class StoreImport
          def initialize(reader, folder, retrieval, databases, rollback: ImportRollback)
            @rollback = rollback
            @reader = reader
            @folder = folder
            @retrieval = retrieval
            @home = File.dirname(databases.fetch(:local).path)
          end

          def call
            lines, counts = imported
            ImportCleanup.new(@folder, @retrieval, @home).call(counts)
            [*lines, "imported metadata: #{Schema.phrase(counts)}"]
          end

          private

          def store = @retrieval.store

          def graphs = Graph.open(home: @home, store:)

          def databases = graphs.databases

          def imported
            @rollback.new(@folder.root).call { checked_import }
          rescue Check::Failed
            raise
          rescue => error
            raise Invalid, "#{store}: the import failed: #{error.message}"
          end

          def checked_import
            Check.new(@folder).call
            import(Roadmaps.new.parse(@folder.root))
          end

          def import(parsed)
            @folder.ignore_databases
            originals = @folder.intent_files.to_h { |path| [path, @folder.read(path)] }
            decisions = Decisions.new.read_decisions(@folder.intent_dirs, originals)
            lines = @reader.read_rows
            [lines, written_metadata(parsed, originals, decisions)]
          end

          def written_metadata(parsed, originals, decisions)
            tally.tap do |counts|
              Decisions.new.write_decisions(databases, decisions, counts)
              Originals.new.keep_changed_originals(databases, @folder, originals, counts)
              Roadmaps.new.migrate_roadmaps(graphs, @folder.root, parsed, counts)
            end
          end

          def tally = Hash.new(0).merge(intents: @retrieval.intents.size, documents: @retrieval.documents.size,
            legacy_intents_data: @retrieval.legacy_intents_data.size, savepoints: @retrieval.savepoints.size)
        end
      end
    end
  end
end
