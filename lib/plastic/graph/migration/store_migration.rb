# frozen_string_literal: true

require_relative "../database"
require_relative "../backup/writer"
require_relative "../schema/gate"
require_relative "../schema/migrator"
require_relative "../schema/migration_list"
require_relative "../schema/state"
require_relative "migration_reason"
require_relative "store_age"

module Plastic
  module Graph
    # Brings the files of one store to the newest version. A store behind is backed up first, whatever the age of its
    # newest backup, and stays behind when that backup fails. The answer is :current, :migrated, or the reason it
    # stayed behind.
    class StoreMigration
      REFERENCES = "references.db"

      def initialize(home, slug, now)
        @home = home
        @slug = slug
        @now = now
        @root = File.join(home, "stores", slug)
      end

      def call
        return :current unless behind?

        StoreAge.call(@root)
        reason = backup_failure
        reason ? "its backup failed (#{reason})" : migrate_files
      rescue SQLite3::Exception, Database::Error, SystemCallError => error
        "it could not be migrated (#{MigrationReason.of(error)})"
      end

      private

      def behind? = SchemaGate.behind?(knowledge_file, [work_file])

      def knowledge_file = File.join(@root, Schema.file(:knowledge))

      def work_file = File.join(@root, Schema.file(:work))

      def references_file = File.join(@root, REFERENCES)

      def release = Database::ConnectionPool.release(@root)

      def migrate_files
        run_migration
        retire_references
        release
        vacuum
        rebuild_search
        :migrated
      rescue SQLite3::Exception, SystemCallError
        release
        Database::ConnectionPool.remove_created(File.join(@root, ""))
        raise
      end

      def connection = Database::ConnectionPool.for(knowledge_file, attach: Database::Store.attachments(knowledge_file))

      def run_migration
        migrating = connection
        return SchemaMigrator.new(migrating, :store).call unless baseline_pending?(migrating)

        with_references(migrating) { SchemaMigrator.new(migrating, :store).call }
      end

      # Only the baseline reads the references file of a beta.2 store; a later migration runs without it.
      def baseline_pending?(migrating) = SchemaState.new(migrating, :store).call.pending.include?(MIGRATIONS.baseline(:store))

      def with_references(migrating)
        migrating.execute("ATTACH DATABASE ? AS refs", [File.exist?(references_file) ? references_file : ":memory:"])
        yield
      ensure
        migrating.execute("DETACH DATABASE refs")
      end

      def retire_references
        ["", "-wal", "-shm", "-journal"].map { |suffix| references_file + suffix }.select { |file| File.file?(file) }.each { |file| File.delete(file) }
      end

      def vacuum
        vacuuming = connection
        %w[main work].each { |schema| vacuuming.execute("VACUUM #{schema}") }
        release
      end

      def rebuild_search = Graph.open(home: @home, store: @slug).retrieval.reindex

      def backup_failure
        Backup::Writer.new(@root, @slug, now: @now, reason: "migration").call
        nil
      rescue Backup::Writer::Error, SQLite3::Exception, SystemCallError => error
        MigrationReason.of(error)
      end
    end
  end
end
