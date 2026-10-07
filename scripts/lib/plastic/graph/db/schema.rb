# frozen_string_literal: true

require_relative "schema_file"

# Every table and every database Plastic keeps. This file is the design: change a table
# here and nowhere else. A table that nothing new reads is marked `legacy: true`.
Plastic::Graph::SCHEMA_FILE = Plastic::Graph::SchemaFile.define(version: 2026_10_07_000000) do
  create_table :routine_runs, key: %i[store tool subject] do |t|
    t.kept :store, :tool
    t.blank :subject
    t.text :at, :finished, :status, :facts, :next_command, :because
    t.integer :exit_code
    t.text :started_at, :updated_at, :session_id
  end

  create_table :sessions, key: %i[session_id] do |t|
    t.kept :session_id
    t.text :harness, :store, :directory, :started_at, :last_turn_at, :ended_at, :end_reason, :note
  end

  create_table :locks, key: %i[store intent_id] do |t|
    t.kept :store, :intent_id, :session_id
    t.text :mode, :taken_at, :renewed_at
  end

  create_table :backups, key: %i[name] do |t|
    t.kept :name
    t.integer :files, :bytes
    t.text :sha256, :at, :session_id
  end

  create_table :intents, key: %i[intent_id origin_id] do |t|
    t.serial :id
    t.kept :intent_id
    t.text :parent_id, :ref
    t.kept :origin_id, :slug, :title
    t.text :kind
    t.status :status
    t.text :disposition, :opened_at, :closed_at, :updated_at
  end

  create_table :clusters, key: %i[name intent_id origin_id] do |t|
    t.kept :name, :intent_id, :origin_id
  end

  create_table :nodes, key: %i[intent_id id origin_id] do |t|
    t.kept :intent_id, :id
    t.text :kind, :title, :criterion, :state, :by, :input, :output, :question, :answer, :reason, :judge, :verdict, :findings
    t.integer :retries
    t.text :updated_at
    t.kept :origin_id
  end

  create_table :edges, key: %i[intent_id from to kind origin_id] do |t|
    t.kept :intent_id, :from, :to, :kind, :origin_id
  end

  create_table :savepoints, key: %i[intent_id position origin_id] do |t|
    t.kept :intent_id
    t.number :position
    t.text :at
    t.kept :text, :origin_id
    t.text :session_id
  end

  create_table :completions, key: %i[intent_id origin_id] do |t|
    t.kept :intent_id, :origin_id, :at, :session_id, :judge, :criteria, :evidence, :outcome_sha256
  end

  create_table :printed, key: %i[path] do |t|
    t.kept :path, :sha256, :at, :origin_id
  end

  create_table :changes, key: [] do |t|
    t.serial :seq
    t.kept :table, :key
    t.operation :operation
    t.text :row
    t.kept :at, :origin_id
  end

  create_table :roadmaps, key: %i[slug origin_id] do |t|
    t.kept :slug, :title
    t.text :goal, :opened_at, :updated_at
    t.kept :origin_id
  end

  create_table :batches, key: %i[roadmap position origin_id] do |t|
    t.kept :roadmap
    t.number :position
    t.kept :title
    t.text :goal, :done, :updated_at
    t.kept :origin_id
  end

  create_table :roadmap_items, key: %i[roadmap item origin_id] do |t|
    t.kept :roadmap, :item
    t.number :batch, :position
    t.text :title, :goal, :done, :intent_id, :mark, :updated_at
    t.kept :origin_id
  end

  create_table :roadmap_edges, key: %i[roadmap from to origin_id] do |t|
    t.kept :roadmap, :from, :to, :kind, :origin_id
  end

  create_table :roadmap_log, key: %i[roadmap position origin_id] do |t|
    t.kept :roadmap
    t.number :position
    t.text :at
    t.kept :text
    t.text :session_id
    t.kept :origin_id
  end

  create_table :archives, key: %i[intent_id origin_id] do |t|
    t.kept :intent_id
    t.text :at
    t.kept :origin_id
    t.text :restored_at, :session_id
  end

  create_table :archive_entries, key: %i[intent_id path origin_id] do |t|
    t.kept :intent_id, :path, :origin_id, :kind
    t.integer :mode
    t.text :mtime
    t.blob :data
  end

  create_table :documents, key: %i[intent_id path origin_id] do |t|
    t.kept :intent_id, :path, :body
    t.text :updated_at
    t.kept :origin_id
  end

  create_table :legacy_intents_data, key: %i[intent_id path origin_id], legacy: true, since: 2026_10_07_000000 do |t|
    t.kept :intent_id, :path, :body
    t.text :updated_at
    t.kept :origin_id
  end

  create_table :document_revisions, key: %i[sha256 intent_id path origin_id] do |t|
    t.kept :sha256, :intent_id, :path, :body, :created_at, :origin_id
  end

  create_table :document_heads, key: %i[intent_id path origin_id] do |t|
    t.kept :intent_id, :path, :sha256, :updated_at, :origin_id
  end

  create_table :document_passages, key: %i[sha256 intent_id path position origin_id] do |t|
    t.kept :sha256, :intent_id, :path
    t.number :position
    t.kept :body
    t.number :line_start, :line_end
    t.kept :origin_id
  end

  create_virtual_table :document_fts,
    using: "fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED)"

  create_table :retrieval_schema, key: %i[name] do |t|
    t.kept :name
    t.number :version
    t.text :completed_at
  end

  create_table :retrieval_backfills, key: %i[name origin_id] do |t|
    t.kept :name, :origin_id
    t.number :version
    t.kept :completed_at
  end

  %i[retrieval_contexts retrieval_discoveries].each do |name|
    create_table name, key: %i[intent_id origin_id] do |t|
      t.kept :intent_id, :origin_id
      t.text :data
      t.kept :updated_at
    end
  end

  create_table :rulings, key: %i[intent_id id origin_id] do |t|
    t.kept :intent_id, :id, :text
    t.text :supersedes, :at, :session_id
    t.kept :origin_id
  end

  create_table :links, key: %i[from_ref to_ref kind origin_id] do |t|
    t.kept :from_ref, :to_ref, :kind
    t.text :at
    t.kept :origin_id
  end

  create_table :sqlar, key: %i[name] do |t|
    t.primary :name
    t.int :mode, :mtime, :sz
    t.blob :data
    t.text :intent_id, :sha256
    t.kept :origin_id
  end

  database :local, "local.db", %i[routine_runs sessions locks backups]
  database :work, "work_graph.db", %i[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items
    roadmap_edges roadmap_log archives archive_entries]
  database :knowledge, "knowledge_graph.db", %i[documents legacy_intents_data document_revisions document_heads document_passages
    document_fts retrieval_schema retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes]
  database :references, "references.db", %i[sqlar printed changes]
end
