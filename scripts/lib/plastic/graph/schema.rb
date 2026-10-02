# frozen_string_literal: true

require_relative "table"
require_relative "intent"
require_relative "roadmap"

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
      # The home keeps `routine_runs`, `sessions` and `locks`, which belong to one machine,
      # not to one store. A store folder keeps the other three tables, one database each.
      #
      # The SQL type of each kind of column; a type not named here is written as it stands.
      TYPES = {
        text: "TEXT", kept: "TEXT NOT NULL", integer: "INTEGER",
        status: "TEXT NOT NULL CHECK(status IN (#{Intent::STATUSES.map { |status| "'#{status}'" }.join(", ")}))"
      }.freeze

      # Each table: the key that names one row, then its columns. `sqlar` is the
      # SQLite archive format, so `sqlite3 -A` lists and extracts the kept files.
      TABLES = {
        routine_runs: [%i[store tool subject], { store: :kept, tool: :kept, subject: "TEXT NOT NULL DEFAULT ''",
                                                 at: :text, finished: :text, status: :text, facts: :text, next_command: :text, because: :text,
                                                 exit_code: :integer, started_at: :text, updated_at: :text, session_id: :text }],
        sessions: [%i[session_id], { session_id: :kept, harness: :text, store: :text, directory: :text,
                                     started_at: :text, last_turn_at: :text, ended_at: :text, end_reason: :text, note: :text }],
        locks: [%i[store intent_id], { store: :kept, intent_id: :kept, session_id: :kept, mode: :text,
                                       taken_at: :text, renewed_at: :text }],
        intents: [%i[intent_id origin_id], { id: "INTEGER PRIMARY KEY AUTOINCREMENT", intent_id: :kept,
                                             parent_id: :text, ref: :text, origin_id: :kept, slug: :kept, title: :kept, kind: :text, status: :status,
                                             disposition: :text, opened_at: :text, closed_at: :text, updated_at: :text }],
        clusters: [%i[name intent_id origin_id], { name: :kept, intent_id: :kept, origin_id: :kept }],
        nodes: [%i[intent_id id origin_id], { intent_id: :kept, id: :kept, kind: :text, title: :text,
                                              criterion: :text, state: :text, by: :text, input: :text, output: :text, question: :text, answer: :text,
                                              reason: :text, judge: :text, verdict: :text, findings: :text, retries: :integer, updated_at: :text,
                                              origin_id: :kept }],
        edges: [%i[intent_id from to kind origin_id], { intent_id: :kept, from: :kept, to: :kept, kind: :kept,
                                                        origin_id: :kept }],
        savepoints: [%i[intent_id position origin_id], { intent_id: :kept, position: "INTEGER NOT NULL",
                                                         at: :text, text: :kept, origin_id: :kept, session_id: :text }],
        documents: [%i[intent_id path origin_id], { intent_id: :kept, path: :kept, body: :kept,
                                                    updated_at: :text, origin_id: :kept }],
        rulings: [%i[intent_id id origin_id], { intent_id: :kept, id: :kept, text: :kept, supersedes: :text,
                                                at: :text, session_id: :text, origin_id: :kept }],
        links: [%i[from_ref to_ref kind origin_id], { from_ref: :kept, to_ref: :kept, kind: :kept,
                                                      at: :text, origin_id: :kept }],
        roadmaps: [%i[slug origin_id], { slug: :kept, title: :kept, goal: :text, opened_at: :text,
                                         updated_at: :text, origin_id: :kept }],
        batches: [%i[roadmap position origin_id], { roadmap: :kept, position: "INTEGER NOT NULL",
                                                    title: :kept, goal: :text, done: :text, updated_at: :text, origin_id: :kept }],
        roadmap_items: [%i[roadmap item origin_id], { roadmap: :kept, item: :kept, batch: "INTEGER NOT NULL",
                                                      position: "INTEGER NOT NULL", title: :kept, goal: :text, done: :text,
                                                      intent_id: :text, mark: :text, updated_at: :text, origin_id: :kept }],
        roadmap_edges: [%i[roadmap from to origin_id], { roadmap: :kept, from: :kept, to: :kept,
                                                         kind: :kept, origin_id: :kept }],
        roadmap_log: [%i[roadmap position origin_id], { roadmap: :kept, position: "INTEGER NOT NULL",
                                                        at: :text, text: :kept, session_id: :text, origin_id: :kept }],
        archives: [%i[intent_id origin_id], { intent_id: :kept, at: :text, origin_id: :kept,
                                              restored_at: :text, session_id: :text }],
        archive_entries: [%i[intent_id path origin_id], { intent_id: :kept, path: :kept, origin_id: :kept,
                                                          kind: :kept, mode: :integer, mtime: :text, data: "BLOB" }],
        backups: [%i[name], { name: :kept, files: :integer, bytes: :integer, sha256: :text,
                              at: :text, session_id: :text }],
        sqlar: [%i[name], { name: "TEXT PRIMARY KEY", mode: "INT", mtime: "INT", sz: "INT", data: "BLOB",
                            intent_id: :text, sha256: :text, origin_id: :kept }],
        printed: [%i[path], { path: :kept, sha256: :kept, at: :kept, origin_id: :kept }],
        changes: [[], { seq: "INTEGER PRIMARY KEY AUTOINCREMENT", table: :kept, key: :kept,
                        operation: "TEXT NOT NULL CHECK(operation IN ('put', 'remove'))", row: :text, at: :kept, origin_id: :kept }]
      }.to_h do |name, (key, columns)|
        [name, Table.new(name:, key:, columns: columns.transform_values { |type| TYPES.fetch(type, type) })]
      end.freeze

      # Each database: its file and its tables.
      DATABASES = {
        home: ["home.db", %i[routine_runs sessions locks backups]],
        work: ["work_graph.db", %i[intents clusters nodes edges savepoints printed changes
          roadmaps batches roadmap_items roadmap_edges roadmap_log archives archive_entries]],
        knowledge: ["knowledge_graph.db", %i[documents rulings links printed changes]],
        references: ["references.db", %i[sqlar printed changes]]
      }.freeze
      STORE = %i[work knowledge references].freeze

      # How the report names the rows of a table: one and many.
      NOUNS = {
        "routine_runs" => ["routine run", "routine runs"], "intents" => %w[intent intents],
        "clusters" => %w[cluster clusters], "nodes" => %w[node nodes], "edges" => %w[edge edges],
        "savepoints" => ["savepoint line", "savepoint lines"], "documents" => %w[document documents],
        "rulings" => %w[ruling rulings], "links" => %w[link links],
        "sqlar" => ["kept file", "kept files"], "printed" => ["printed file", "printed files"],
        "sessions" => %w[session sessions], "locks" => %w[lock locks],
        "roadmaps" => %w[roadmap roadmaps], "batches" => %w[batch batches],
        "roadmap_items" => %w[item items], "roadmap_edges" => ["roadmap edge", "roadmap edges"],
        "roadmap_log" => ["roadmap log line", "roadmap log lines"], "archives" => %w[archive archives],
        "archive_entries" => ["archive entry", "archive entries"], "backups" => %w[backup backups]
      }.freeze

      def self.file(key) = DATABASES.fetch(key).first

      def self.fetch(key) = DATABASES.fetch(key).last.map { |name| TABLES.fetch(name).ddl }.join("\n")

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
