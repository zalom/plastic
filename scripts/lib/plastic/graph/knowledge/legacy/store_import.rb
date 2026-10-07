# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../../config"
require_relative "decisions"
require_relative "roadmaps"
require_relative "originals"
require_relative "import_rollback"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The complete first sync of one legacy store, with rollback and preserved originals.
        class StoreImport
          def initialize(reader, folder, retrieval, databases)
            @reader = reader
            @folder = folder
            @retrieval = retrieval
            @home = File.dirname(databases.fetch(:local).path)
          end

          def call
            lines, counts = imported(parsed_roadmaps)
            remove_imported(counts) if remove_after_import?
            [*lines, "imported metadata: #{Schema.phrase(counts)}"]
          end

          private

          def store = @retrieval.store

          def graphs = Graph.open(home: @home, store:)

          def databases = graphs.databases

          def parsed_roadmaps
            parsed = Roadmaps.new.parse(@folder.root)
            problems = parsed.values.flat_map(&:problems)
            raise Invalid, problems.join("; ") if problems.any?

            parsed
          end

          # A store that fails halfway gets its folder back as it was, databases
          # gone, so the next run imports it again instead of skipping it.
          def imported(parsed)
            ImportRollback.new(@folder.root).call { import(parsed) }
          rescue => error
            raise Invalid, "#{store}: the import failed: #{error.message}"
          end

          def import(parsed)
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

          def tally = Hash.new(0).merge(intents: @retrieval.intents.size, documents: @retrieval.documents.size, savepoints: @retrieval.savepoints.size)

          def remove_after_import? = Config.new(@home).flag(%w[migrate remove_after_import], default: false)

          # Runs only after the store imported with no error. A failure here keeps
          # the rows already written and says what was left in place.
          def remove_imported(counts)
            archive_done_intents(graphs.work, counts)
            @folder.delete(StoreFolder::LEGACY_INDEX)
          rescue => error
            raise Invalid, "#{store}: imported, but removing the imported files stopped: #{error.message}"
          end

          def archive_done_intents(work, counts)
            archived = done_intent_ids.count { |id| work.archive_intent(id).first }
            counts[:archived] += archived if archived.positive?
          end

          def done_intent_ids = @retrieval.intents.select(&:closed?).map(&:intent_id)
        end
      end
    end
  end
end
