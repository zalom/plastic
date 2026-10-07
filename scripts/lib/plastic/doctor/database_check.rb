# frozen_string_literal: true

require "sqlite3"
require_relative "../graph/schema"

module Plastic
  module Doctor
    class DatabaseCheck
      def initialize(path, key)
        @path = path
        @key = key
      end

      def problem
        return "#{path} is missing" unless File.file?(path)

        missing = declared - present
        "#{file} lacks the #{missing.one? ? "table" : "tables"} #{missing.join(", ")}" unless missing.empty?
      rescue SQLite3::Exception => error
        "#{file} cannot be read: #{error.message}"
      end

      private

      attr_reader :path, :key

      def file = File.basename(path)

      def declared = Graph::Schema.databases.fetch(key).last.map(&:to_s)

      def present
        connection = SQLite3::Database.new(path, readonly: true)
        connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
      ensure
        connection&.close
      end
    end
  end
end
