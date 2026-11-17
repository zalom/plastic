# frozen_string_literal: true

require_relative "../database"
require_relative "../origin"
require_relative "../backup/writer"
require_relative "home_copy"
require_relative "home_rename"

module Plastic
  module Graph
    # Brings the databases of a home to the newest version of their
    # sequences. The install and the update run it, and nothing else does.
    # A store whose files are behind is backed up first, whatever the age of
    # its newest backup; when that backup fails, the store stays behind and
    # the run goes on with the other stores.
    class SchemaRunner
      # `migrated` names the stores that moved; `failed` maps each store that stayed behind to the reason.
      Report = Data.define(:migrated, :failed)

      # The files of a store in the order they migrate: knowledge first, so the tables that work copies into exist.
      ORDER = %i[knowledge work retrieval].freeze

      # `only` names one store to migrate; the home database is checked either way.
      def initialize(home:, now: Time.now, sequences: SchemaSequences::SEQUENCES, only: nil)
        @home = home
        @only = only
        @now = now
        @sequences = sequences
      end

      def call
        results = store_slugs.to_h { |slug| [slug, migrate_store(slug)] }
        results["home"] = migrate_home
        Report.new(migrated: named(results, :migrated), failed: reasons(results))
      end

      private

      def named(results, result) = results.select { |_slug, outcome| outcome == result }.keys

      def reasons(results) = results.select { |_slug, outcome| outcome.is_a?(String) }

      def migrate_home
        path = [current, former].find { |file| File.exist?(file) }
        return :current unless path

        reason = preparation_failure(path)
        return reason if reason

        local = Database.open_local(@home).fetch(:local)
        return :current if local.version >= SchemaSequences.newest(:home)

        local.migrate(@sequences)
        :migrated
      rescue SQLite3::Exception, Database::Error, SystemCallError, HomeRename::Taken => error
        "it could not be migrated (#{first_line(error)})"
      end

      def former = File.join(@home, "local.db")

      def current = File.join(@home, "plastic.db")

      def preparation_failure(path)
        reason = copy_failure(path) if version_of(path) < SchemaSequences.newest(:home)
        return "the copy of its database failed (#{reason})" if reason

        HomeRename.new(former, current).call if path == former
        nil
      end

      def version_of(path) = SQLite3::Database.open(path, readonly: true) { |db| db.get_first_value("PRAGMA user_version").to_i }

      def copy_failure(path)
        HomeCopy.new(path, File.join(@home, "backups"), @now).call
        nil
      rescue SQLite3::Exception, SystemCallError, HomeCopy::Exists => error
        first_line(error)
      end

      def first_line(error) = error.message.lines.first.to_s.strip

      def store_slugs
        folder = File.join(@home, "stores")
        File.directory?(folder) ? Dir.children(folder).sort.select { |name| File.directory?(File.join(folder, name)) && (@only.nil? || name == @only) } : []
      end

      def databases(slug)
        root = File.join(@home, "stores", slug)
        Database.open_store(root, Origin.new(@home)).select { |_key, database| File.exist?(database.path) }.values
      end

      def migrate_store(slug)
        outcome = migrate_store_to_newest(slug)
        outcome.is_a?(String) ? outcome : retire_references(slug, outcome)
      rescue SQLite3::Exception, Database::Error, Plastic::Invalid => error
        "it could not be migrated (#{first_line(error)})"
      end

      def migrate_store_to_newest(slug)
        files = databases(slug)
        return :current if files.all? { |database| database.version >= SchemaSequences.newest(:store) }

        reason = backup_failure(slug)
        reason ? "its backup failed (#{reason})" : migrate_store_files(slug, files)
      end

      # references.db goes only after the knowledge file, stamped with the migration that copied it, answers each of its rows.
      def retire_references(slug, outcome)
        root = File.join(@home, "stores", slug)
        knowledge = File.join(root, Schema.file(:knowledge))
        SchemaStore6.retire(knowledge, File.join(root, SchemaStore6::FILE)) if File.file?(knowledge) && version_of(knowledge) >= SchemaStore6::STAMP
        outcome
      rescue SchemaStore6::Mismatch => error
        "its references.db was kept (#{first_line(error)})"
      end

      def migrate_store_files(slug, files)
        migrate_files(files)
        built = databases(slug).reject { |database| files.map(&:key).include?(database.key) }
        return :migrated if built.empty?

        migrate_files(databases(slug))
        files.find { |database| database.key == :knowledge }&.vacuum
        :migrated
      end

      def migrate_files(files)
        siblings = files.to_h { |database| [database.key, database.path] }
        files.sort_by { |database| ORDER.index(database.key) || ORDER.size }.each { |database| database.migrate(@sequences, siblings:) }
        :migrated
      end

      def backup_failure(slug)
        Backup::Writer.new(File.join(@home, "stores", slug), slug, now: @now, reason: "migration").call
        nil
      rescue Backup::Writer::Error, SQLite3::Exception, SystemCallError => error
        first_line(error)
      end
    end
  end
end
