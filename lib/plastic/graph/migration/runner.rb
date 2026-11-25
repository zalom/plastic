# frozen_string_literal: true

require_relative "home_migration"
require_relative "records_newer"
require_relative "migration_ledger"
require_relative "migration_reason"
require_relative "store_migration"

module Plastic
  module Graph
    # Brings the databases of a home to the newest version of their sequences. The install and the update run it, and
    # nothing else does. A store that stays behind does not stop the run: the others go on. Each migration that ran on a
    # store adds an up row to the ledger in plastic.db, once the home is current.
    class SchemaRunner
      # `migrated` names the stores that moved; `failed` maps each store that stayed behind to the reason; `notes` holds
      # the lines the migrations of the stores report.
      # `newer` maps each database that records versions this code does not know to those versions; the run leaves it as it is.
      Report = Data.define(:migrated, :failed, :notes, :newer) do
        def self.of(results, notes = [])
          grouped = results.group_by { |_slug, outcome| group(outcome) }
          new(migrated: grouped.fetch(:migrated, []).map(&:first), failed: grouped.fetch(:failed, []).to_h, notes:,
            newer: grouped.fetch(:newer, []).to_h { |slug, outcome| [slug, outcome.versions] })
        end

        def self.group(outcome)
          case outcome
          when String then :failed
          when RecordsNewer then :newer
          else outcome
          end
        end

        def initialize(migrated:, failed:, notes: [], newer: {}) = super

        def newer_lines = newer.map { |store, versions| "migrate: #{store} was written by newer code (it records #{versions.join(", ")}); update leaves it as it is" }

        def behind_lines = failed.map { |store, reason| "migrate: #{store} stays behind because #{reason}; fix the cause and run plastic update" }

        # Every line a person reads: the stores that stayed behind, then the notes.
        def lines = behind_lines + newer_lines + notes
      end

      # `only` names one store to migrate; the home database is checked either way. `selection` is the sync selection of
      # the machine, which says which kept files a store keeps.
      def initialize(home:, now:, selection:, only: nil)
        @home = home
        @only = only
        @now = now
        @run = StoreMigration::Run.new(selection:)
      end

      def call
        migrations = store_slugs.to_h { |slug| [slug, StoreMigration.new(@home, slug, @now, run: @run)] }
        results = migrations.transform_values(&:call)
        home = HomeMigration.new(@home, @now)
        results["home"] = home.call
        Report.of(results, notes(migrations, home, results))
      end

      private

      # The notes of the stores and of the home, then the line of a ledger write that failed.
      def notes(migrations, home, results)
        migrated = migrations.select { |slug, _| results[slug] == :migrated }
        migrations.values.flat_map(&:notes) + home.notes + ledger_notes(migrated, results["home"])
      end

      # Records the up rows of the stores that migrated, or answers the line that says which stores the ledger lacks.
      def ledger_notes(migrated, home)
        return [] if migrated.empty?
        return ["migrate: plastic.db stays behind, so its ledger does not record the migrations of #{migrated.keys.join(", ")}"] if home.is_a?(String)

        written = []
        reason = MigrationLedger.write(@home, @now) { |ledger| migrated.each { |slug, migration| written << ups(ledger, slug, migration) } }
        reason ? [ledger_gap(migrated.keys, written, reason)] : []
      end

      # Writes the up rows of one store and answers its slug.
      def ups(ledger, slug, migration)
        ledger.ups(slug, migration.ledger)
        slug
      end

      # The note of a ledger write that failed: the stores whose up rows it wrote, and those whose rows it lacks.
      def ledger_gap(stores, written, reason)
        lacking = (stores - written).join(", ")
        return "migrate: the ledger in plastic.db does not record the migrations of #{lacking} (#{reason})" if written.empty?

        "migrate: the ledger in plastic.db records the migrations of #{written.join(", ")} but not those of #{lacking} (#{reason})"
      end

      def store_slugs
        folder = File.join(@home, "stores")
        File.directory?(folder) ? Dir.children(folder).sort.select { |name| File.directory?(File.join(folder, name)) && (@only.nil? || name == @only) } : []
      end
    end
  end
end
