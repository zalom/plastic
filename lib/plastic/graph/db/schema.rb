# frozen_string_literal: true

require_relative "schema_file"

# Every table and every database Plastic keeps. This file is the design: change a table
# here and nowhere else. A table that nothing new reads is marked `legacy: true`.
Plastic::Graph::SCHEMA_FILE = Plastic::Graph::SchemaFile.define(version: 2026_11_17_000000) do
  create_table :command_runs, key: %i[store tool subject] do |t|
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

  create_table :settings, key: %i[scope key] do |t|
    t.kept :scope, :key, :value
  end

  create_table :intents, key: %i[intent_id origin_id] do |t|
    t.serial :id
    t.kept :intent_id
    t.text :parent_id, :ref
    t.kept :origin_id, :slug, :title
    t.text :kind
    t.status :status
    t.text :disposition, :reason, :opened_at, :closed_at, :updated_at
  end

  create_table :clusters, key: %i[name intent_id origin_id] do |t|
    t.kept :name, :intent_id, :origin_id
  end

  create_table :nodes, key: %i[intent_id id origin_id] do |t|
    t.kept :intent_id, :id
    t.text :kind, :title, :criterion, :state, :input, :output, :question, :answer, :reason, :judge, :verdict, :findings
    t.text :updated_at
    t.kept :origin_id
    t.text :claimed_by, :claimed_at, :seen_at, :answered_at
  end

  create_table :runs, key: %i[intent_id node_id number origin_id] do |t|
    t.kept :intent_id, :node_id
    t.number :number
    t.blank :agent, :session_id
    t.text :started_at, :ended_at, :result
    t.kept :origin_id
  end

  create_table :edges, key: %i[intent_id from to kind origin_id] do |t|
    t.kept :intent_id, :from, :to, :kind, :origin_id
  end

  create_table :work_log, key: %i[intent_id position origin_id] do |t|
    t.kept :intent_id
    t.number :position
    t.text :at
    t.blank :phase, :node
    t.text :session_id
    t.kept :kind
    t.blank :path, :sha256, :text
    t.kept :origin_id
    t.text :write_id
  end

  create_table :work_log_pending, key: %i[write_id] do |t|
    t.kept :write_id, :intent_id
    t.text :at
    t.blank :phase, :node
    t.text :session_id
    t.kept :kind
    t.blank :path, :sha256, :text
    t.kept :origin_id
  end

  create_table :completions, key: %i[intent_id origin_id] do |t|
    t.kept :intent_id, :origin_id, :at, :session_id, :judge, :criteria, :evidence, :outcome_sha256
  end

  create_table :approvals, key: %i[intent_id origin_id], since: 2026_10_09_000000 do |t|
    t.kept :intent_id, :origin_id
    t.text :at, :session_id
  end

  create_table :verdicts, key: %i[intent_id round origin_id], since: 2026_10_09_000000 do |t|
    t.kept :intent_id
    t.number :round
    t.kept :origin_id, :verdict, :findings
    t.text :at, :session_id
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

  database :local, "plastic.db", %i[command_runs sessions settings printed]
  database :work, "work_graph.db", %i[nodes edges work_log printed changes roadmaps batches roadmap_items roadmap_edges roadmap_log runs]
  database :knowledge, "knowledge_graph.db", %i[intents clusters completions approvals verdicts archives archive_entries work_log_pending documents
    legacy_intents_data document_revisions document_heads retrieval_contexts retrieval_discoveries rulings links printed changes]
  database :retrieval, "retrieval_graph.db", %i[document_passages document_fts]
  database :references, "references.db", %i[sqlar printed changes]
end
