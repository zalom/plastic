# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require "fileutils"

# A throwaway home whose registered store alpha the previous release wrote: it records every version before the drop
# of document_revisions, holds a row there, and keeps in sqlar a file that only its row holds. `migrated_previous_home`
# runs the migrations on it, which keep both rows in legacy.db.
module PreviousStore
  DROP = "20261119000000"
  ROADMAP = "originals/roadmaps/plan.md"
  MIGRATED_AT = Time.utc(2026, 11, 19, 12, 0, 0)
  REVISIONS = <<~SQL
    CREATE TABLE document_revisions("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL,
      "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
    INSERT INTO document_revisions VALUES ('sha', '1', 'intent.md', 'old text', 'then', 'origin');
    INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES ('#{ROADMAP}', 420, 0, 0, CAST('old roadmap' AS BLOB), 'o');
  SQL

  # The store files were made by an earlier process, so this one forgets that it made them.
  def previous_home
    home = File.join(Dir.mktmpdir, ".plastic")
    FileUtils.mkdir_p(File.join(home, "stores", "alpha"))
    File.write(File.join(home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
      database.execute_batch(REVISIONS)
      database.execute("DELETE FROM schema_migrations WHERE version = ?", [DROP])
    end
    home
  end

  def migrated_previous_home = previous_home.tap { |home| migrate_store(home) }

  def migrate_store(home, now: MIGRATED_AT)
    Plastic::Graph::SchemaRunner.new(home:, now:, selection: Plastic::Graph::Knowledge::SyncSelection.none).call.tap { forget(home) }
  end

  def forget(home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    Plastic::Graph::Database::ConnectionPool.created.clear
  end

  def alpha_file(home, name) = File.join(home, "stores", "alpha", name)

  def alpha_rows(home, name, sql)
    SQLite3::Database.open(alpha_file(home, name), readonly: true) { |database| database.execute(sql) }
  end

  def recorded(home) = alpha_rows(home, "knowledge_graph.db", "SELECT version FROM schema_migrations ORDER BY version").flatten

  def legacy_tables(home) = alpha_rows(home, "legacy.db", "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").flatten

  def ledger_rows(home)
    SQLite3::Database.open(File.join(home, "plastic.db"), readonly: true) do |database|
      database.execute("SELECT store, version, event, moved, undoable FROM store_migrations ORDER BY id")
    end
  end

  def store_bytes(home) = Dir.glob(alpha_file(home, "*.db")).sort.to_h { |path| [File.basename(path), File.binread(path)] }

  def backup_folders(home) = Dir.glob(alpha_file(home, "backups/*")).select { |path| File.directory?(path) }.map { |path| File.basename(path) }.sort
end
