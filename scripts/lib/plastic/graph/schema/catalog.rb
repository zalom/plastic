# frozen_string_literal: true

require_relative "declaration"

module Plastic
  module Graph
    # Owns the static table and database declarations that generate Plastic's DDL.
    module SchemaCatalog
      TYPES = {
        text: "TEXT", kept: "TEXT NOT NULL", integer: "INTEGER", int: "INT", blob: "BLOB",
        number: "INTEGER NOT NULL", blank: "TEXT NOT NULL DEFAULT ''", primary: "TEXT PRIMARY KEY",
        serial: "INTEGER PRIMARY KEY AUTOINCREMENT",
        operation: "TEXT NOT NULL CHECK(operation IN ('put', 'remove'))",
        status: "TEXT NOT NULL CHECK(status IN (#{Knowledge::Intent::STATUSES.map { |status| "'#{status}'" }.join(", ")}))"
      }.freeze

      DECLARED = {
        routine_runs: "store tool subject | store:kept tool:kept subject:blank at finished status facts next_command because exit_code:integer started_at updated_at session_id",
        sessions: "session_id | session_id:kept harness store directory started_at last_turn_at ended_at end_reason note",
        locks: "store intent_id | store:kept intent_id:kept session_id:kept mode taken_at renewed_at",
        intents: "intent_id origin_id | id:serial intent_id:kept parent_id ref origin_id:kept slug:kept title:kept kind status:status disposition opened_at closed_at updated_at",
        completions: "intent_id origin_id | intent_id:kept origin_id:kept at:kept session_id:kept judge:kept criteria:kept evidence:kept outcome_sha256:kept",
        clusters: "name intent_id origin_id | name:kept intent_id:kept origin_id:kept",
        nodes: "intent_id id origin_id | intent_id:kept id:kept kind title criterion state by input output question answer reason judge verdict findings retries:integer updated_at origin_id:kept",
        edges: "intent_id from to kind origin_id | intent_id:kept from:kept to:kept kind:kept origin_id:kept",
        savepoints: "intent_id position origin_id | intent_id:kept position:number at text:kept origin_id:kept session_id",
        documents: "intent_id path origin_id | intent_id:kept path:kept body:kept updated_at origin_id:kept",
        rulings: "intent_id id origin_id | intent_id:kept id:kept text:kept supersedes at session_id origin_id:kept",
        links: "from_ref to_ref kind origin_id | from_ref:kept to_ref:kept kind:kept at origin_id:kept",
        roadmaps: "slug origin_id | slug:kept title:kept goal opened_at updated_at origin_id:kept",
        batches: "roadmap position origin_id | roadmap:kept position:number title:kept goal done updated_at origin_id:kept",
        roadmap_items: "roadmap item origin_id | roadmap:kept item:kept batch:number position:number title goal done intent_id mark updated_at origin_id:kept",
        roadmap_edges: "roadmap from to origin_id | roadmap:kept from:kept to:kept kind:kept origin_id:kept",
        roadmap_log: "roadmap position origin_id | roadmap:kept position:number at text:kept session_id origin_id:kept",
        archives: "intent_id origin_id | intent_id:kept at origin_id:kept restored_at session_id",
        archive_entries: "intent_id path origin_id | intent_id:kept path:kept origin_id:kept kind:kept mode:integer mtime data:blob",
        backups: "name | name:kept files:integer bytes:integer sha256 at session_id",
        sqlar: "name | name:primary mode:int mtime:int sz:int data:blob intent_id sha256 origin_id:kept",
        printed: "path | path:kept sha256:kept at:kept origin_id:kept",
        changes: "| seq:serial table:kept key:kept operation:operation row at:kept origin_id:kept"
      }.freeze

      TABLES = DECLARED.transform_values { |line| Declaration.parse(line) }.merge(RetrievalSchema::TABLES).to_h do |name, (key, columns)|
        [name, Table.new(name:, key:, columns: columns.transform_values { |type| TYPES.fetch(type, type) })]
      end.freeze

      DATABASES = {
        local: ["local.db", %i[routine_runs sessions locks backups]],
        work: ["work_graph.db", %i[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items roadmap_edges roadmap_log archives archive_entries]],
        knowledge: ["knowledge_graph.db", %i[documents document_revisions document_heads document_passages document_fts retrieval_schema retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes]],
        references: ["references.db", %i[sqlar printed changes]]
      }.freeze
      STORE = %i[work knowledge references].freeze
    end
  end
end
