# frozen_string_literal: true

require "sqlite3"
require_relative "../database"
require_relative "../behind"

module Plastic
  module Graph
    # Refuses a store older than beta.2 before anything is written: its intents have no `reason` column, and no migration reads it.
    class StoreAge
      def self.call(root) = new(root).call

      def initialize(root)
        @root = root
      end

      def call
        raise TooOld, "the store #{File.basename(@root)} is older than beta.2; open it once with beta.2, then run plastic update" unless columns.include?("reason")
      end

      private

      def work_file = File.join(@root, Schema.file(:work))

      def columns
        SQLite3::Database.open(work_file, readonly: true) { |database| database.execute("SELECT name FROM pragma_table_info('intents')").flatten }
      rescue SQLite3::Exception => error
        raise Database::Error, "#{work_file}: #{error.message}"
      end
    end
  end
end
