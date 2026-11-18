# frozen_string_literal: true

require_relative "../database"
require_relative "../backup/writer"
require_relative "../schema/gate"
require_relative "../schema/migrator"
require_relative "../schema/migration_list"
require_relative "../schema/state"
require_relative "migration_reason"
require_relative "store_age"
require_relative "store_compaction"

module Plastic
  module Graph
    # Brings the files of one store to the newest version. A store behind is backed up first, whatever the age of its
    # newest backup, and stays behind when that backup fails. The answer is :current, :migrated, or the reason it
    # stayed behind.
    class StoreMigration
      REFERENCES = "references.db"

      def initialize(home, slug, now, compaction: StoreCompaction)
        @home = home
        @slug = slug
        @now = now
        @compaction = compaction
      end

      def call
        return :current unless behind?

        StoreAge.call(root) if baseline_pending?
        reason = backup_failure
        reason ? "its backup failed (#{reason})" : migrate_files
      rescue SQLite3::Exception, Database::Error, SystemCallError => error
        "it could not be migrated (#{MigrationReason.of(error)})"
      end

      private

      def root = File.join(@home, "stores", @slug)

      def behind? = SchemaGate.behind?(knowledge_file, [File.join(root, Schema.file(:work))])

      def knowledge_file = File.join(root, Schema.file(:knowledge))

      def references_file = File.join(root, REFERENCES)

      def release = Database::ConnectionPool.release(root)

      def migrate_files
        run_migration
        retire_references
        release
        @compaction.call(@home, @slug)
        :migrated
      end

      def run_migration
        migrating = Database::ConnectionPool.for(knowledge_file, attach: Database::Store.attachments(knowledge_file))
        with_references(migrating) { SchemaMigrator.new(migrating, :store).call }
      rescue SQLite3::Exception, SystemCallError
        release
        Database::ConnectionPool.remove_created(File.join(root, ""))
        raise
      end

      # Only the baseline reads the work file and the references file of a beta.2 store; a later migration needs neither.
      def baseline_pending? = !File.file?(knowledge_file) || SchemaState.of_file(knowledge_file, :store).pending.include?(MIGRATIONS.baseline(:store))

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
