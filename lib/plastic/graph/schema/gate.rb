# frozen_string_literal: true

require_relative "../behind"

module Plastic
  module Graph
    # The check a database passes on its first use in a process. The stamp of the main file says whether the whole
    # database is current. A new, empty database gets the declared schema of each of its files and the newest stamp. A
    # database at the newest version passes. A database behind is refused after one wait for the write lock, because
    # another session may be migrating it; a database ahead of this code is refused too. Nothing here migrates an old
    # file: the install and the update do, through SchemaRunner.
    class SchemaGate
      MAIN = "main"

      # True when a file of the store holds tables and the main file is unstamped, which no new store is.
      def self.behind?(path, files)
        existing = [path, *files].select { |file| File.file?(file) }
        return false if existing.empty? || (File.file?(path) && stamp_of(path) != 0)

        existing.any? { |file| holding_tables?(file) }
      rescue SQLite3::Exception
        false
      end

      def self.stamp_of(path) = SQLite3::Database.open(path, readonly: true) { |database| database.get_first_value("PRAGMA user_version") }

      def self.holding_tables?(path) = SQLite3::Database.open(path, readonly: true) { |database| database.get_first_value("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").positive? }

      # `layouts` maps each schema of the connection, nil for a database of one file, to the schema key that builds it; the first is the main file.
      def initialize(connection, layouts:, file:, newest: SchemaMigrator::VERSION)
        @connection = connection
        @layouts = layouts
        @newest = newest
        @file = file
      end

      def call
        version = stamped
        return build_missing_files if version == @newest

        raise Ahead, refusal("is newer than this code (version #{version}, code #{@newest})") if version > @newest

        settle(version)
      rescue SQLite3::BusyException
        raise Behind, refusal("is busy and behind this code (version #{version}, code #{@newest})")
      end

      private

      def pragma = "PRAGMA #{prefix(@layouts.keys.first)}user_version"

      def prefix(schema) = schema && "#{schema}."

      def stamped = @connection.get_first_value(pragma).to_i

      def empty? = @layouts.keys.all? { |schema| empty_schema?(schema) }

      def empty_schema?(schema) = @connection.get_first_value("SELECT COUNT(*) FROM #{prefix(schema)}sqlite_master WHERE name NOT LIKE 'sqlite_%'").zero?

      # An attached file that was lost, such as the derived retrieval file, is built again empty; the stamp of the main file stays.
      def build_missing_files
        lost = @layouts.keys.compact.select { |schema| empty_schema?(schema) }
        return if lost.empty?

        under_write_lock { lost.each { |schema| @connection.execute_batch(Schema.fetch(@layouts.fetch(schema), schema:)) if empty_schema?(schema) } }
      end

      def settle(version)
        return if empty? && build_layout

        verify_current(version)
      end

      # Builds the declared schema of every file and stamps it in one transaction under the write lock. A second
      # session that waited for the lock finds the tables there and builds nothing.
      def build_layout
        under_write_lock do
          next false unless empty?

          @layouts.each { |schema, key| @connection.execute_batch(Schema.fetch(key, schema:)) }
          @connection.execute("#{pragma} = #{@newest}")
          true
        end
      end

      def verify_current(version)
        current = under_write_lock { stamped }
        raise Behind, refusal("is behind this code (version #{version}, code #{@newest})") unless current == @newest
      end

      # A call already inside a transaction holds the write lock or will; a call outside one takes it here.
      def under_write_lock(&)
        return yield if @connection.transaction_active?

        @connection.transaction(:immediate, &)
      end

      def refusal(reason) = "#{@file} #{reason}; run plastic update"
    end
  end
end
