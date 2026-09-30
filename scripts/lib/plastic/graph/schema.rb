# frozen_string_literal: true

require_relative "table"
require_relative "intent"

module Plastic
  module Graph
    # The tables of the databases. A column is named after the member of the
    # record it holds, so `Intent.from_h(row)` reads a row with no mapping.
    #
    # The home keeps one database for what belongs to one machine. Each store
    # folder keeps three, and each of those has a `changes` table, the log of
    # every write, and a `printed` table, the hash of every file printed from
    # its rows. The whole design is in docs/contributing/ARCHITECTURE.md.
    module Schema
      TEXT = "TEXT"
      KEPT = "TEXT NOT NULL"
      STATUS = "TEXT NOT NULL CHECK(status IN (#{Intent::STATUSES.map { |status| "'#{status}'" }.join(", ")}))".freeze

      def self.table(name, key, **columns) = Table.new(name:, columns:, key:)

      ROUTINE_RUNS = table(:routine_runs, %i[store tool subject], store: KEPT, tool: KEPT, subject: "TEXT NOT NULL DEFAULT ''",
        at: TEXT, finished: TEXT, status: TEXT, facts: TEXT, next_command: TEXT, because: TEXT, exit_code: "INTEGER",
        started_at: TEXT, updated_at: TEXT)
      INTENTS = table(:intents, %i[intent_id origin_id], id: "INTEGER PRIMARY KEY AUTOINCREMENT", intent_id: KEPT,
        parent_id: TEXT, ref: TEXT, origin_id: KEPT, slug: KEPT, title: KEPT, kind: TEXT, status: STATUS,
        disposition: TEXT, opened_at: TEXT, closed_at: TEXT, updated_at: TEXT)
      CLUSTERS = table(:clusters, %i[name intent_id origin_id], name: KEPT, intent_id: KEPT, origin_id: KEPT)
      NODES = table(:nodes, %i[intent_id id origin_id], intent_id: KEPT, id: KEPT, kind: TEXT, title: TEXT,
        criterion: TEXT, state: TEXT, by: TEXT, input: TEXT, output: TEXT, question: TEXT, answer: TEXT, reason: TEXT,
        judge: TEXT, verdict: TEXT, findings: TEXT, retries: "INTEGER", updated_at: TEXT, origin_id: KEPT)
      EDGES = table(:edges, %i[intent_id from to kind origin_id], intent_id: KEPT, from: KEPT, to: KEPT, kind: KEPT,
        origin_id: KEPT)
      SAVEPOINTS = table(:savepoints, %i[intent_id position origin_id], intent_id: KEPT, position: "INTEGER NOT NULL",
        at: TEXT, text: KEPT, origin_id: KEPT)
      DOCUMENTS = table(:documents, %i[intent_id path origin_id], intent_id: KEPT, path: KEPT, body: KEPT,
        updated_at: TEXT, origin_id: KEPT)
      # The SQLite archive format, so `sqlite3 -A` lists and extracts the kept files.
      SQLAR = table(:sqlar, %i[name], name: "TEXT PRIMARY KEY", mode: "INT", mtime: "INT", sz: "INT", data: "BLOB",
        intent_id: TEXT, sha256: TEXT, origin_id: KEPT)
      PRINTED = table(:printed, %i[path], path: KEPT, sha256: KEPT, at: KEPT, origin_id: KEPT)
      CHANGES = table(:changes, [], seq: "INTEGER PRIMARY KEY AUTOINCREMENT", table: KEPT, key: KEPT,
        operation: "TEXT NOT NULL CHECK(operation IN ('put', 'remove'))", row: TEXT, at: KEPT, origin_id: KEPT)

      DATABASES = {
        home: [ROUTINE_RUNS],
        work: [INTENTS, CLUSTERS, NODES, EDGES, SAVEPOINTS, PRINTED, CHANGES],
        knowledge: [DOCUMENTS, PRINTED, CHANGES],
        references: [SQLAR, PRINTED, CHANGES]
      }.freeze
      FILES = { home: "home.db", work: "work_graph.db", knowledge: "knowledge_graph.db", references: "references.db" }.freeze
      STORE = %i[work knowledge references].freeze
      TABLES = DATABASES.values.flatten.to_h { |table| [table.name, table] }.freeze

      # How the report names the rows of a table: one and many.
      NOUNS = {
        "routine_runs" => ["routine run", "routine runs"], "intents" => %w[intent intents],
        "clusters" => %w[cluster clusters], "nodes" => %w[node nodes], "edges" => %w[edge edges],
        "savepoints" => ["savepoint line", "savepoint lines"], "documents" => %w[document documents],
        "sqlar" => ["kept file", "kept files"], "printed" => ["printed file", "printed files"]
      }.freeze

      def self.fetch(key) = DATABASES.fetch(key).map(&:ddl).join("\n")

      def self.table_named(name) = TABLES.fetch(name.to_sym)

      # A count of rows with its noun: "1 routine run", "2 routine runs".
      def self.tally(table, count)
        name = table.to_s
        one, many = NOUNS.fetch(name) { [name, name] }
        "#{count} #{(count == 1) ? one : many}"
      end

      # Counts by table as one phrase: "1 routine run, 2 notes, and 1 tally".
      def self.phrase(counts)
        *rest, last = counts.map { |table, count| tally(table, count) }
        return last if rest.empty?

        (rest.size == 1) ? "#{rest.first} and #{last}" : "#{rest.join(", ")}, and #{last}"
      end
    end
  end
end
