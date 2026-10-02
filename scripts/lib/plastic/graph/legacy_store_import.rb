# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../config"
require_relative "legacy_decisions"
require_relative "legacy_roadmaps"
require_relative "legacy_originals"
require_relative "import_rollback"

module Plastic
  module Graph
    # The complete first sync of one legacy store, with rollback and preserved originals.
    class LegacyStoreImport
      StoreReport = Data.define(:store, :skipped, :counts, :problems)

      DONE_STATES = %w[done abandoned].freeze

      def initialize(reader, folder, retrieval, databases)
        @reader, @folder, @retrieval, @databases = reader, folder, retrieval, databases
        @home = File.dirname(databases.fetch(:home).path)
        @decisions = LegacyDecisions.new
        @originals = LegacyOriginals.new
        @roadmaps = LegacyRoadmaps.new
      end

      def call
        result = imported_report(@home, @retrieval.store, @folder)
        raise Invalid, result.problems.join("; ") if result.problems.any?

        [*@lines, "imported metadata: #{Schema.phrase(result.counts)}"]
      end

      private

      def report(slug, counts: {}, problems: [], skipped: false) = StoreReport.new(store: slug, skipped:, counts:, problems:)

      def imported_report(home, slug, folder)
        root = folder.root
        parsed = @roadmaps.parse(root)
        problems = parsed.values.flat_map(&:problems)
        return report(slug, problems:) if problems.any?

        counts = rolled_back_on_error(root) { run_import(home, slug, root, folder, parsed) }
      rescue => e
        report(slug, problems: ["#{slug}: the import failed: #{e.message}"])
      else
        removed_after_import(home, slug, folder, counts)
      end

      def remove_after_import? = Config.new(@home).flag(%w[migrate remove_after_import], default: false)

      # Runs only after the store imported with no error. A failure here keeps
      # the rows already written and says what was left in place.
      def removed_after_import(home, slug, folder, counts)
        return report(slug, counts:) unless remove_after_import?

        graphs = Graph.open(home:, store: slug, session: @session)
        archive_done_intents(graphs.work, graphs.retrieval, counts)
        folder.delete(StoreFolder::LEGACY_INDEX)
        report(slug, counts:)
      rescue => e
        report(slug, counts:, problems: ["#{slug}: imported, but removing the imported files stopped: #{e.message}"])
      end

      # A store that fails halfway gets its folder back as it was, databases
      # gone, so the next run imports it again instead of skipping it.
      def rolled_back_on_error(root)
        ImportRollback.new(root).call { yield }
      end

      def run_import(home, slug, root, folder, parsed)
        originals = folder.intent_files.to_h { |path| [path, folder.read(path)] }
        decisions = @decisions.read_decisions(folder.intent_dirs, originals)
        graphs = Graph.open(home:, store: slug, session: @session)
        counts = Hash.new(0)
        @lines = @reader.read_rows
        tally_sync(counts, graphs.retrieval)
        @decisions.write_decisions(graphs.databases, decisions, counts)
        @originals.keep_changed_originals(graphs.databases, folder, originals, counts)
        @roadmaps.migrate_roadmaps(graphs, root, parsed, counts)
        counts
      end

      def tally_sync(counts, retrieval)
        counts[:intents] = retrieval.intents.size
        counts[:documents] = retrieval.documents.size
        counts[:savepoints] = retrieval.savepoints.size
      end

      # Optional cleanup follows a successful import.
      def archive_done_intents(work, retrieval, counts)
        retrieval.intents.each do |intent|
          next unless DONE_STATES.include?(intent.status)

          ok, = work.archive_intent(intent.intent_id)
          counts[:archived] += 1 if ok
        end
      end
    end
  end
end
