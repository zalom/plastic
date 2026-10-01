# frozen_string_literal: true

module Plastic
  class TestCase
    # A database in the test's home, with tables for the database tests.
    module DatabaseHelper
      SCHEMA = <<~SQL
        CREATE TABLE IF NOT EXISTS routine_runs(id INTEGER PRIMARY KEY, name TEXT UNIQUE, data BLOB);
        CREATE TABLE IF NOT EXISTS tallies(name TEXT);
        CREATE TABLE IF NOT EXISTS notes(name TEXT);
        CREATE TABLE IF NOT EXISTS stored(store TEXT, name TEXT);
      SQL

      def database = (@database ||= Plastic::Graph::Database.new(File.join(@home, "work_graph.db"), SCHEMA))

      def insert(name, table: :routine_runs)
        database.transaction { |batch| batch.insert(table, { name: }) }
      end
    end
  end
end
