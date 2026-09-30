# frozen_string_literal: true

module Plastic
  module Graph
    # The tables of the databases. A column is named after the member of the
    # record it holds, so `RoutineRun.from_h(row)` reads a row with no
    # mapping. `store` names the store a row belongs to: the databases sit at
    # the home and hold every store.
    module Schema
      WORK = <<~SQL
        CREATE TABLE IF NOT EXISTS routine_runs(store TEXT NOT NULL, tool TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '',
          at TEXT, finished TEXT, status TEXT, facts TEXT, next_command TEXT, because TEXT, exit_code INTEGER,
          started_at TEXT, updated_at TEXT, PRIMARY KEY(store, tool, subject));
      SQL

      # How the report names the rows of a table: one and many.
      NOUNS = {"routine_runs" => ["routine run", "routine runs"]}.freeze

      def self.noun(table, count)
        one, many = NOUNS.fetch(table.to_s) { [table.to_s, table.to_s] }
        (count == 1) ? one : many
      end

      def self.fetch(key) = {work: WORK}.fetch(key)
    end
  end
end
