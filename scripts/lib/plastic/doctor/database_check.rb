# frozen_string_literal: true

require "sqlite3"
require_relative "../graph/schema"

module Plastic
  module Doctor
    class DatabaseCheck
      def self.lacking(file, missing) = ("#{file} lacks the #{missing.one? ? "table" : "tables"} #{missing.join(", ")}" unless missing.empty?)

      def self.tables(path)
        SQLite3::Database.new(path, readonly: true).then do |connection|
          connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
        ensure
          connection.close
        end
      end

      def initialize(path, key)
        @path = path
        @key = key
      end

      def problem
        return "#{path} is missing" unless File.file?(path)

        DatabaseCheck.lacking(file, declared - DatabaseCheck.tables(path))
      rescue SQLite3::Exception => error
        "#{file} cannot be read: #{error.message}"
      end

      private

      attr_reader :path, :key

      def file = File.basename(path)

      def declared = Graph::Schema.databases.fetch(key).last.map(&:to_s)
    end
  end
end
