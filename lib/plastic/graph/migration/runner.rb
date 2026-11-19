# frozen_string_literal: true

require_relative "home_migration"
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
      Report = Data.define(:migrated, :failed, :notes) do
        def self.of(results, notes = [])
          grouped = results.group_by { |_slug, outcome| outcome.is_a?(String) ? :failed : outcome }
          new(migrated: grouped.fetch(:migrated, []).map(&:first), failed: grouped.fetch(:failed, []).to_h, notes:)
        end

        def initialize(migrated:, failed:, notes: []) = super

        def behind_lines = failed.map { |store, reason| "migrate: #{store} stays behind because #{reason}; fix the cause and run plastic update" }

        # Every line a person reads: the stores that stayed behind, then the notes.
        def lines = behind_lines + notes
      end

      # `only` names one store to migrate; the home database is checked either way. `selection` is the sync selection of
      # the machine, which says which kept files a store keeps.
      def initialize(home:, now:, selection:, only: nil)
        @home = home
        @only = only
        @now = now
        @selection = selection
      end

      def call
        migrations = store_slugs.to_h { |slug| [slug, StoreMigration.new(@home, slug, @now, selection: @selection)] }
        results = migrations.transform_values(&:call)
        results["home"] = HomeMigration.new(@home, @now).call
        Report.of(results, migrations.values.flat_map(&:notes) + ledger_notes(migrations.select { |slug, _| results[slug] == :migrated }, results["home"]))
      end

      private

      # Records the up rows of the stores that migrated, or answers the line that says why the ledger holds none.
      def ledger_notes(migrated, home)
        return [] if migrated.empty?

        stores = migrated.keys.join(", ")
        return ["migrate: plastic.db stays behind, so its ledger does not record the migrations of #{stores}"] if home.is_a?(String)

        ledger = MigrationLedger.new(Database.open_local(@home).fetch(:local), @now)
        migrated.each { |slug, migration| ledger.ups(slug, migration.ledger) }
        []
      rescue SQLite3::Exception, Database::Error, SystemCallError => error
        ["migrate: the ledger in plastic.db does not record the migrations of #{stores} (#{MigrationReason.of(error)})"]
      end

      def store_slugs
        folder = File.join(@home, "stores")
        File.directory?(folder) ? Dir.children(folder).sort.select { |name| File.directory?(File.join(folder, name)) && (@only.nil? || name == @only) } : []
      end
    end
  end
end
