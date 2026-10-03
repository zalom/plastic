# frozen_string_literal: true

module Plastic
  module Graph
    # Owns the static table and database declarations that generate Plastic's DDL.
    module SchemaCatalog
      TYPES = {
        text: "TEXT", kept: "TEXT NOT NULL", integer: "INTEGER",
        status: "TEXT NOT NULL CHECK(status IN (#{Knowledge::Intent::STATUSES.map { |status| "'#{status}'" }.join(", ")}))"
      }.freeze

      TABLES = {
        routine_runs: [%i[store tool subject], { store: :kept, tool: :kept, subject: "TEXT NOT NULL DEFAULT ''", at: :text, finished: :text, status: :text, facts: :text, next_command: :text, because: :text, exit_code: :integer, started_at: :text, updated_at: :text, session_id: :text }],
        sessions: [%i[session_id], { session_id: :kept, harness: :text, store: :text, directory: :text, started_at: :text, last_turn_at: :text, ended_at: :text, end_reason: :text, note: :text }],
        locks: [%i[store intent_id], { store: :kept, intent_id: :kept, session_id: :kept, mode: :text, taken_at: :text, renewed_at: :text }],
        intents: [%i[intent_id origin_id], { id: "INTEGER PRIMARY KEY AUTOINCREMENT", intent_id: :kept, parent_id: :text, ref: :text, origin_id: :kept, slug: :kept, title: :kept, kind: :text, status: :status, disposition: :text, opened_at: :text, closed_at: :text, updated_at: :text }],
        completions: [%i[intent_id origin_id], { intent_id: :kept, origin_id: :kept, at: :kept, session_id: :kept, judge: :kept, criteria: :kept, evidence: :kept, outcome_sha256: :kept }],
        clusters: [%i[name intent_id origin_id], { name: :kept, intent_id: :kept, origin_id: :kept }],
        nodes: [%i[intent_id id origin_id], { intent_id: :kept, id: :kept, kind: :text, title: :text, criterion: :text, state: :text, by: :text, input: :text, output: :text, question: :text, answer: :text, reason: :text, judge: :text, verdict: :text, findings: :text, retries: :integer, updated_at: :text, origin_id: :kept }],
        edges: [%i[intent_id from to kind origin_id], { intent_id: :kept, from: :kept, to: :kept, kind: :kept, origin_id: :kept }],
        savepoints: [%i[intent_id position origin_id], { intent_id: :kept, position: "INTEGER NOT NULL", at: :text, text: :kept, origin_id: :kept, session_id: :text }],
        documents: [%i[intent_id path origin_id], { intent_id: :kept, path: :kept, body: :kept, updated_at: :text, origin_id: :kept }],
        rulings: [%i[intent_id id origin_id], { intent_id: :kept, id: :kept, text: :kept, supersedes: :text, at: :text, session_id: :text, origin_id: :kept }],
        links: [%i[from_ref to_ref kind origin_id], { from_ref: :kept, to_ref: :kept, kind: :kept, at: :text, origin_id: :kept }],
        roadmaps: [%i[slug origin_id], { slug: :kept, title: :kept, goal: :text, opened_at: :text, updated_at: :text, origin_id: :kept }],
        batches: [%i[roadmap position origin_id], { roadmap: :kept, position: "INTEGER NOT NULL", title: :kept, goal: :text, done: :text, updated_at: :text, origin_id: :kept }],
        roadmap_items: [%i[roadmap item origin_id], { roadmap: :kept, item: :kept, batch: "INTEGER NOT NULL", position: "INTEGER NOT NULL", title: :text, goal: :text, done: :text, intent_id: :text, mark: :text, updated_at: :text, origin_id: :kept }],
        roadmap_edges: [%i[roadmap from to origin_id], { roadmap: :kept, from: :kept, to: :kept, kind: :kept, origin_id: :kept }],
        roadmap_log: [%i[roadmap position origin_id], { roadmap: :kept, position: "INTEGER NOT NULL", at: :text, text: :kept, session_id: :text, origin_id: :kept }],
        archives: [%i[intent_id origin_id], { intent_id: :kept, at: :text, origin_id: :kept, restored_at: :text, session_id: :text }],
        archive_entries: [%i[intent_id path origin_id], { intent_id: :kept, path: :kept, origin_id: :kept, kind: :kept, mode: :integer, mtime: :text, data: "BLOB" }],
        backups: [%i[name], { name: :kept, files: :integer, bytes: :integer, sha256: :text, at: :text, session_id: :text }],
        sqlar: [%i[name], { name: "TEXT PRIMARY KEY", mode: "INT", mtime: "INT", sz: "INT", data: "BLOB", intent_id: :text, sha256: :text, origin_id: :kept }],
        printed: [%i[path], { path: :kept, sha256: :kept, at: :kept, origin_id: :kept }],
        changes: [[], { seq: "INTEGER PRIMARY KEY AUTOINCREMENT", table: :kept, key: :kept, operation: "TEXT NOT NULL CHECK(operation IN ('put', 'remove'))", row: :text, at: :kept, origin_id: :kept }]
      }.merge(RetrievalSchema::TABLES).to_h do |name, (key, columns)|
        [name, Table.new(name:, key:, columns: columns.transform_values { |type| TYPES.fetch(type, type) })]
      end.freeze

      DATABASES = {
        home: ["home.db", %i[routine_runs sessions locks backups]],
        work: ["work_graph.db", %i[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items roadmap_edges roadmap_log archives archive_entries]],
        knowledge: ["knowledge_graph.db", %i[documents document_revisions document_heads document_passages document_fts retrieval_schema retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes]],
        references: ["references.db", %i[sqlar printed changes]]
      }.freeze
      STORE = %i[work knowledge references].freeze
    end
  end
end
