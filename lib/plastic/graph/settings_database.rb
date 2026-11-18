# frozen_string_literal: true

require "sqlite3"
require_relative "database"
require_relative "behind"
require_relative "origin"

module Plastic
  module Graph
    # The machine database as the settings see it: reads that come back empty
    # when the database is missing, busy or behind, writes in one transaction,
    # and the origin id of the home.
    class SettingsDatabase
      FILE = "plastic.db"

      def initialize(home)
        @home = home
      end

      def rows(sql, **binds)
        return [] unless File.file?(File.join(@home, FILE))

        local.rows(sql, **binds)
      rescue SQLite3::Exception, Database::Error, OutOfStep
        []
      end

      def transaction(&) = local.transaction(&)

      def origin_id = Origin.new(@home).id

      private

      def local = Database.open_local(@home).fetch(:local)
    end
  end
end
