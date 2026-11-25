# frozen_string_literal: true

require_relative "../database"
require_relative "../schema/gate"
require_relative "home_copy"
require_relative "home_rename"
require_relative "../schema/migrator"
require_relative "../schema/state"
require_relative "migration_reason"
require_relative "records_newer"
require_relative "utc_times"

module Plastic
  module Graph
    # Brings the home database to the newest version. A database behind is copied into backups first, and the former
    # name local.db is renamed to plastic.db. The answer is :current, :migrated, or the reason it stayed behind. `notes`
    # names, after each migration, every time the UTC migration left as it was because it names no real moment. plastic.db
    # has no down: the copy in backups/ is the way back.
    class HomeMigration
      # What each home migration that drops data says the data is, in the words of LegacyKeep::KINDS. The first one drops
      # the tables backups and locks: the backup folders on disk are the record of each backup, and the node claims of
      # each store say who holds what, so nothing of the owner's is lost. The second deletes the rows of the retired
      # setting migrate.drop_document_revisions, which no command reads. A test fails when one is missing here.
      KINDS = { "20261117000000" => :rebuilt, "20261125090000" => :rebuilt }.freeze

      def initialize(home, now)
        @home = home
        @now = now
        @notes = []
      end

      attr_reader :notes

      def call
        path = [current, former].find { |file| File.exist?(file) }
        path ? (RecordsNewer.read(path, :home) || migrate(path)) : :current
      rescue SQLite3::Exception, Database::Error, SystemCallError, HomeRename::Taken => error
        "it could not be migrated (#{MigrationReason.of(error)})"
      end

      private

      def former = File.join(@home, "local.db")

      def current = File.join(@home, "plastic.db")

      def migrate(path) = preparation_failure(path) || advance

      def advance = local.schema_state.behind? ? migrated : :current

      def local = (@local ||= Database.open_local(@home).fetch(:local))

      def migrated
        local.migrate
        note_unreadable
        :migrated
      end

      def note_unreadable
        unreadable = UtcTimes.unreadable(Database::ConnectionPool.for(current), UtcTimes::HOME_COLUMNS)
        UtcTimes::Result.new(changed: 0, unreadable:).line("plastic.db")&.then { |line| @notes << line }
      end

      def preparation_failure(path)
        reason = copy_failure(path) if SchemaState.of_file(path, :home).behind?
        return "the copy of its database failed (#{reason})" if reason

        HomeRename.new(former, current).call if path == former
        nil
      end

      def copy_failure(path)
        HomeCopy.new(path, File.join(@home, "backups"), @now).call
        nil
      rescue SQLite3::Exception, SystemCallError, HomeCopy::Exists => error
        MigrationReason.of(error)
      end
    end
  end
end
