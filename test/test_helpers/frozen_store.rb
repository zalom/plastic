# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require_relative "../../lib/plastic/graph/schema/sequences"

# Two real database files of a store at the layout of store migration 3, the work and the knowledge file, with rows in the tables that move.
module FrozenStore
  Layout = Plastic::Graph::SchemaStore1::Layout::TEXT

  def build_pair(folder: Dir.mktmpdir)
    @folder = folder
    @work = SQLite3::Database.new(File.join(folder, "work_graph.db"), results_as_hash: true)
    @knowledge = SQLite3::Database.new(File.join(folder, "knowledge_graph.db"), results_as_hash: true)
    @work.execute_batch(Layout.fetch(:work) + Plastic::Graph::SchemaStore2::TEXT.fetch(:work) + Plastic::Graph::SchemaStore3::TEXT.fetch(:work))
    @knowledge.execute_batch(Layout.fetch(:knowledge))
    [@work, @knowledge].each { |database| database.execute("PRAGMA user_version = 3") }
    seed_moving_rows
  end

  def knowledge_path = File.join(@folder, "knowledge_graph.db")

  def seed_moving_rows
    seed_intent_rows
    seed_node_rows
  end

  def seed_intent_rows
    @work.execute_batch(<<~SQL)
      INSERT INTO intents (intent_id, origin_id, slug, title, status, opened_at) VALUES ('1', 'o', 'alpha', 'Alpha', 'in_progress', '2026-11-01'), ('2', 'o', 'beta', 'Beta', 'done', '2026-11-02');
      INSERT INTO clusters (name, intent_id, origin_id) VALUES ('core', '1', 'o');
      INSERT INTO completions (intent_id, origin_id, at, session_id, judge, criteria, evidence, outcome_sha256) VALUES ('2', 'o', 't', 's', 'verdict', '{}', '{}', 'h');
      INSERT INTO approvals (intent_id, origin_id, at, session_id) VALUES ('1', 'o', 't', 's');
      INSERT INTO verdicts (intent_id, round, origin_id, verdict, findings) VALUES ('1', 1, 'o', 'pass', '[]');
      INSERT INTO archives (intent_id, origin_id, at) VALUES ('2', 'o', 't');
      INSERT INTO archive_entries (intent_id, path, origin_id, kind, mode, mtime, data) VALUES ('2', 'a.md', 'o', 'file', 420, 't', x'00ff10');
      INSERT INTO work_log_pending (write_id, intent_id, at, kind, text, origin_id) VALUES ('w-1', '1', 't', 'noted', 'owed', 'o');
    SQL
  end

  def seed_node_rows
    @work.execute_batch(<<~SQL)
      INSERT INTO nodes (intent_id, id, kind, title, state, origin_id) VALUES ('1', 'n1', 'task', 'Node', 'open', 'o');
      INSERT INTO printed (path, sha256, at, origin_id) VALUES ('store/index.json', 'a', 't', 'o'), ('1--alpha/graph.json', 'b', 't', 'o'), ('1--alpha/work.log', 'c', 't', 'o'), ('roadmaps/r.md', 'd', 't', 'o');
      INSERT INTO changes ("table", "key", operation, at, origin_id) VALUES ('intents', '1', 'put', 't', 'o'), ('nodes', 'n1', 'put', 't', 'o');
    SQL
  end

  def migrate_work = Plastic::Graph::SchemaStore4.apply(@work, :work, { knowledge: knowledge_path })

  def count(database, table) = database.get_first_value("SELECT count(*) FROM \"#{table}\"")

  def tables(database) = database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }
end
