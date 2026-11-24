# frozen_string_literal: true

require_relative "../database"
require_relative "../backup/writer"
require_relative "../schema/gate"
require_relative "../schema/migrator"
require_relative "../schema/migration_list"
require_relative "../schema/state"
require_relative "kept_files_cleanup"
require_relative "legacy_keep"
require_relative "legacy_pages"
require_relative "legacy_trim"
require_relative "migration_reason"
require_relative "records_newer"
require_relative "report_rows"
require_relative "roadmap_needs"
require_relative "store_age"
require_relative "store_compaction"
require_relative "utc_times"

module Plastic
  module Graph
    # Brings the files of one store to the newest version. A store behind is backed up first, whatever the age of its
    # newest backup, and stays behind when that backup fails. The answer is :current, :migrated, or the reason it
    # stayed behind. `notes` holds the lines its data steps and its compaction report. The migration that keeps in sqlar
    # only the files a sync reads takes the sync `selection` of the machine. What a migration removes is kept in legacy.db
    # in the same transaction, and `ledger` holds an entry for each migration that ran. A run that made legacy.db and kept
    # nothing in it removes the file.
    class StoreMigration
      REFERENCES = "references.db"
      # The data steps by the version they belong to. Each runs once, while its version is pending.
      DATA_STEPS = { "20261119000000" => KeptFilesCleanup, "20261119180000" => ReportRows, "20261119190000" => LegacyTrim,
                     "20261120090000" => LegacyPages, "20261121090000" => UtcTimes,
                     "20261123120000" => RoadmapNeeds }.freeze

      # What the settings of the machine choose for a run: the sync `selection`, and the held versions `released` by
      # their switch, which the run applies.
      Run = Data.define(:selection, :released)

      def initialize(home, slug, now, run:, compaction: StoreCompaction)
        @home = home
        @slug = slug
        @now = now
        @selection = run.selection
        @released = run.released
        @notes = []
        @ledger = []
        @compaction = compaction
      end

      attr_reader :notes, :ledger

      def call
        return newer if newer
        return compacted(:current) unless behind?

        StoreAge.call(root) if pending?(MIGRATIONS.baseline(:store))
        reason = backup_failure
        reason ? "its backup failed (#{reason})" : migrate_files
      rescue SQLite3::Exception, Database::Error, SystemCallError => error
        "it could not be migrated (#{MigrationReason.of(error)})"
      end

      private

      def root = File.join(@home, "stores", @slug)

      # A store written by newer code is left as it is: nothing here may open it, since the gate refuses it.
def newer = (@newer ||= newer_reading)

def newer_reading
  return unless File.file?(knowledge_file)

  reading = SchemaState.of_file(knowledge_file, :store, released: @released)
  RecordsNewer.new(reading.unknown) if reading.ahead?
end

      def behind? = SchemaGate.behind?(knowledge_file, [File.join(root, Schema.file(:work))], released: @released)

      def knowledge_file = File.join(root, Schema.file(:knowledge))

      def references_file = File.join(root, REFERENCES)

      def release = Database::ConnectionPool.release(root)

      def migrate_files
        run_migration
        retire_references
        release
        compacted(:migrated)
      end

      # Compacts the store while a file of it is not on incremental auto vacuum, so any run tries a failed compaction
      # again. A failure is its own note, since the migration before it holds.
      def compacted(state)
        @compaction.call(@home, @slug) if StoreCompaction.due?(root)
        state
      rescue SQLite3::Exception, Database::Error, SystemCallError => error
        @notes << "compact: #{@slug} was not compacted (#{MigrationReason.of(error)}); run plastic update to try again"
        state
      end

      # The data steps run in the transaction of the migration, after the schema steps, so the baseline has made sqlar.
      def run_migration
        data = DATA_STEPS.select { |version, _step| pending?(version) }
        attach = attachments
        migrating = Database::ConnectionPool.for(knowledge_file, attach:)
        with_references(migrating) { migrating.atomically { migrate_rows(migrating, data) } }
        settle_legacy(attach.key?(:legacy) && kept_nothing?(migrating))
      rescue SQLite3::Exception, Database::Error, SystemCallError
        release
        Database::ConnectionPool.remove_created(File.join(root, ""))
        raise
      end

      def legacy_file = File.join(root, LegacyKeep::FILE)

      def kept_nothing?(migrating) = migrating.get_first_value("SELECT count(*) FROM legacy.sqlite_master").zero?

      # Removes legacy.db when this run made it and kept nothing in it, else keeps it from a later removal of made files.
      def settle_legacy(empty)
        return Database::ConnectionPool.forget_created(legacy_file) unless empty

        release
        Database::ConnectionPool.remove_created(legacy_file)
      end

      # legacy.db is attached only while a pending migration keeps what it removes, so no other run makes the file.
      def attachments = Database::Store.attachments(knowledge_file).merge(LegacyKeep.attachment(root, pending))

      def migrate_rows(migrating, data)
        keep = LegacyKeep.new(migrating)
        SchemaMigrator.new(migrating, :store, before: keep, released: @released).call
        data.each { |version, step| step.new(migrating, root, @selection, keep: keep.at(version)).call.line(@slug)&.then { |line| @notes << line } }
        @ledger = keep.entries
      end

      # Every store version when the knowledge file is missing, else the versions it lacks.
      def pending = File.file?(knowledge_file) ? SchemaState.of_file(knowledge_file, :store, released: @released).pending : MIGRATIONS.versions(:store) - (MIGRATIONS.held(:store) - @released)

      def pending?(version) = pending.include?(version)

      # Only the baseline reads the work file and the references file of a beta.2 store; a later migration needs neither.
      def baseline_pending? = pending?(MIGRATIONS.baseline(:store))

      # Attaches the references file while the baseline runs, the one migration that reads it.
      def with_references(migrating)
        return yield unless baseline_pending?

        begin
          migrating.execute("ATTACH DATABASE ? AS refs", [File.exist?(references_file) ? references_file : ":memory:"])
          yield
        ensure
          migrating.execute("DETACH DATABASE refs")
        end
      end

      def retire_references
        ["", "-wal", "-shm", "-journal"].map { |suffix| references_file + suffix }.select { |file| File.file?(file) }.each { |file| File.delete(file) }
      end

      def backup_failure
        Backup::Writer.new(root, @slug, now: @now, reason: "migration").call
        nil
      rescue Backup::Writer::Error, SQLite3::Exception, SystemCallError => error
        MigrationReason.of(error)
      end
    end
  end
end
