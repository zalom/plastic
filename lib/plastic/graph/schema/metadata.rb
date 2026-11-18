# frozen_string_literal: true

module Plastic
  module Graph
    module SchemaMetadata
      NOUNS = {
        "completions" => ["completion", "completions"],
        "retrieval_contexts" => ["retrieval context", "retrieval contexts"],
        "retrieval_discoveries" => ["retrieval discovery", "retrieval discoveries"],
        "command_runs" => ["command run", "command runs"], "intents" => %w[intent intents],
        "clusters" => %w[cluster clusters], "nodes" => %w[node nodes], "runs" => %w[run runs], "edges" => %w[edge edges],
        "work_log" => ["work log line", "work log lines"],
        "documents" => %w[document documents],
        "legacy_intents_data" => ["legacy file", "legacy files"], "rulings" => %w[ruling rulings], "links" => %w[link links],
        "sqlar" => ["kept file", "kept files"], "printed" => ["printed file", "printed files"],
        "sessions" => %w[session sessions],
        "settings" => %w[setting settings], "chat_messages" => ["chat message", "chat messages"],
        "roadmaps" => %w[roadmap roadmaps], "batches" => %w[batch batches],
        "roadmap_items" => %w[item items], "roadmap_edges" => ["roadmap edge", "roadmap edges"],
        "roadmap_log" => ["roadmap log line", "roadmap log lines"], "archives" => %w[archive archives],
        "archive_entries" => ["archive entry", "archive entries"], "approvals" => ["go-ahead", "go-aheads"], "verdicts" => %w[verdict verdicts],
        "document_revisions" => ["document revision", "document revisions"],
        "document_heads" => ["document head", "document heads"], "document_passages" => ["passage", "passages"],
        "document_fts" => ["search entry", "search entries"]
      }.freeze
    end
  end
end
