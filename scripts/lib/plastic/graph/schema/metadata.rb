# frozen_string_literal: true

module Plastic
  module Graph
    module SchemaMetadata
      NOUNS = {
        "completions" => ["completion", "completions"],
        "retrieval_contexts" => ["retrieval context", "retrieval contexts"],
        "retrieval_discoveries" => ["retrieval discovery", "retrieval discoveries"],
        "routine_runs" => ["routine run", "routine runs"], "intents" => %w[intent intents],
        "clusters" => %w[cluster clusters], "nodes" => %w[node nodes], "edges" => %w[edge edges],
        "savepoints" => ["savepoint line", "savepoint lines"], "documents" => %w[document documents],
        "legacy_intents_data" => ["legacy file", "legacy files"], "rulings" => %w[ruling rulings], "links" => %w[link links],
        "sqlar" => ["kept file", "kept files"], "printed" => ["printed file", "printed files"],
        "sessions" => %w[session sessions], "locks" => %w[lock locks],
        "roadmaps" => %w[roadmap roadmaps], "batches" => %w[batch batches],
        "roadmap_items" => %w[item items], "roadmap_edges" => ["roadmap edge", "roadmap edges"],
        "roadmap_log" => ["roadmap log line", "roadmap log lines"], "archives" => %w[archive archives],
        "archive_entries" => ["archive entry", "archive entries"], "backups" => %w[backup backups]
      }.freeze

      MIGRATIONS = {
        knowledge: "INSERT OR IGNORE INTO \"retrieval_schema\" (\"name\", \"version\") VALUES ('retrieval', 1);"
      }.freeze
    end
  end
end
