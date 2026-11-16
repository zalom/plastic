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
  return :current unless File.exist?(former) || File.exist?(current)

  reason = rename_failure
  return reason if reason

  local = Database.open_local(@home).fetch(:local)
  return :current if local.version >= SchemaSequences.newest(:home)

  local.migrate(@sequences)
  :migrated
rescue SQLite3::Exception, Database::Error => error
  "it could not be migrated (#{first_line(error)})"
end

def former = File.join(@home, "local.db")

def current = File.join(@home, "plastic.db")

def rename_failure
  return unless File.exist?(former) && !File.exist?(current)

  reason = copy_failure
  return "the copy of its database failed (#{reason})" if reason

  HomeRename.new(former, current).call
  nil
end

def copy_failure
  HomeCopy.new(former, File.join(@home, "backups"), @now).call
  nil
rescue SQLite3::Exception, SystemCallError => error
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
        files = databases(slug)
        return :current if files.all? { |database| database.version >= SchemaSequences.newest(:store) }
        reason = backup_failure(slug)
        return "its backup failed (#{reason})" if reason

        files.each { |database| database.migrate(@sequences) }
        :migrated
      rescue SQLite3::Exception, Database::Error => error
        "it could not be migrated (#{first_line(error)})"
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
