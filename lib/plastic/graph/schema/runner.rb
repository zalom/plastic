# frozen_string_literal: true

require_relative "../database"
require_relative "../origin"
require_relative "../knowledge/backup/writer"

module Plastic
  module Graph
    # Brings the databases of a home to the newest version of their
    # sequences. The install and the update run it, and nothing else does.
    # A store whose files are behind is backed up first, whatever the age of
    # its newest backup; when that backup fails, the store stays behind and
    # the run goes on with the other stores.
    class SchemaRunner
      # `failed` names the stores that stayed behind, `migrated` the ones that moved.
      Report = Data.define(:migrated, :failed)

      # `only` names one store to migrate; the home database is checked either way.
      def initialize(home:, now: Time.now, sequences: SchemaSequences::SEQUENCES, only: nil)
        @home = home
        @only = only
        @now = now
        @sequences = sequences
      end

      def call
        migrate_home
        results = store_slugs.to_h { |slug| [slug, migrate_store(slug)] }
        Report.new(migrated: named(results, :migrated), failed: named(results, :failed))
      end

      private

      def named(results, result) = results.select { |_slug, outcome| outcome == result }.keys

      def migrate_home
        return unless %w[local.db home.db].any? { |name| File.exist?(File.join(@home, name)) }

        Database.open_local(@home).fetch(:local).migrate(@sequences)
      end

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
        return :failed unless backed_up?(slug)

        files.each { |database| database.migrate(@sequences) }
        :migrated
      rescue SQLite3::Exception, Database::Error
        :failed
      end

      def backed_up?(slug)
        Knowledge::Backup::Writer.new(File.join(@home, "stores", slug), slug, now: @now, reason: "migration").call
        true
      rescue Knowledge::Backup::Writer::Error, SQLite3::Exception, SystemCallError
        false
      end
    end
  end
end
