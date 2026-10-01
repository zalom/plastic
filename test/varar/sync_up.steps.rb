# frozen_string_literal: true

require "varar"
require "json"
require "tmpdir"
require_relative "support/kernel_command"

module SyncUpAcceptance
  SPEC = "SELECT body FROM documents WHERE path = 'spec.md'"
  TITLE = "SELECT title FROM intents"

  # Rewrites store/index.json with each intent entry changed by the block.
  def self.edit_index(kernel, clusters: [])
    data = JSON.parse(kernel.read("store/index.json"))
    data["intents"] = data["intents"].map { |entry| yield(entry) }
    kernel.write("store/index.json", JSON.generate(data.merge("clusters" => clusters)))
  end

  GRAPH = { "nodes" => [{ "id" => "n1", "kind" => "build" }], "edges" => [{ "from" => "n1", "to" => "n2", "kind" => "needs" }] }.freeze

  # Each change: what it does by hand, then the database and the query that show the rows after the call.
  CHANGES = {
    "none" => [->(_kernel) {}, "knowledge_graph.db", SPEC],
    "spec.md edited" => [->(kernel) { kernel.write("store/1--alpha/spec.md", "# Spec, edited\n") }, "knowledge_graph.db", SPEC],
    "graph.json given a node" => [->(kernel) { kernel.write("store/1--alpha/graph.json", JSON.generate(GRAPH)) }, "work_graph.db",
      "SELECT \"from\" || ' needs ' || \"to\" FROM edges"],
    "title renamed in index.json" => [->(kernel) { edit_index(kernel) { |entry| entry.merge("title" => "Alpha, renamed") } },
      "work_graph.db", TITLE],
    "cluster added in index.json" => [->(kernel) { edit_index(kernel, clusters: [{ "name" => "Core", "intents" => ["1"] }], &:itself) },
      "work_graph.db", "SELECT name || ' holds ' || intent_id FROM clusters"],
    "savepoint.md emptied" => [->(kernel) { kernel.write("store/1--alpha/savepoint.md", "") }, "work_graph.db",
      "SELECT count(*) || ' savepoint lines' FROM savepoints"],
    "a folder with no intent row" => [->(kernel) { kernel.write("store/7--stray/spec.md", "# Stray\n") }, "knowledge_graph.db", SPEC],
    "index.json of another origin" => [->(kernel) { edit_index(kernel) { |entry| entry.merge("origin_id" => "beef") } },
      "work_graph.db", TITLE],
    "index.json that does not parse" => [->(kernel) { kernel.write("store/index.json", "{") }, "work_graph.db", TITLE]
  }.freeze
end

steps do
  sensor("the change, the exit code, the result and the rows") do |_state, row|
    Dir.mktmpdir("varar-sync-up") do |home|
      kernel = KernelCommand.alpha(home)
      change, database, query = SyncUpAcceptance::CHANGES.fetch(row["change"])
      change.call(kernel)
      call = kernel.run("sync", "up")
      rows = kernel.rows(database, query).flatten.map { |value| value.to_s.chomp }
      # The parser's own words after "does not parse" differ between JSON versions.
      row.merge("exit" => call.code.to_s, "result" => call.result.sub(/(does not parse):.*/, '\1'), "rows" => rows.join(", "))
    end
  end
end
