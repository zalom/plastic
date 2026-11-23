# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require "fileutils"
require_relative "../../lib/plastic/graph/migration/migration_down"

# A throwaway home whose registered store alpha the previous release wrote: it records every version before the drop
# of document_revisions, holds a row there, and keeps in sqlar a file that only its row holds. `migrated_previous_home`
# runs the migrations on it, which keep the earlier revision in legacy.db and print the file back.
module PreviousStore
  DROP = "20261119000000"
  REPORTS = "20261119180000"
  TRIM = "20261119190000"
  PAGES = "20261120090000"
  UTC = "20261121090000"
  USAGE = "20261123090000"
  USAGE_COLUMNS = %w[harness worker_session usage_note model input_tokens output_tokens cache_read_tokens cache_write_tokens cost_usd].freeze
  ROADMAP = "originals/roadmaps/plan.md"
  MIGRATED_AT = Time.utc(2026, 11, 19, 12, 0, 0)
  REVISIONS = <<~SQL
    CREATE TABLE IF NOT EXISTS main."document_revisions"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
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
      database.execute("DELETE FROM schema_migrations WHERE version IN (?, ?, ?, ?, ?, ?)", [DROP, REPORTS, TRIM, PAGES, UTC, USAGE])
    end
    drop_usage_columns(home)
  end

  def drop_usage_columns(home)
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| USAGE_COLUMNS.each { |column| database.execute("ALTER TABLE runs DROP COLUMN #{column}") } }
    home
  end

  def migrated_previous_home = previous_home.tap { |home| migrate_store(home) }

  def migrate_store(home, now: MIGRATED_AT)
    Plastic::Graph::SchemaRunner.new(home:, now:, selection: Plastic::Graph::Knowledge::SyncSelection.none, released: Plastic::Graph::MigrationList::HELD.keys).call.tap { forget(home) }
  end

  # Undoes the run usage migration, the time migration, the page migration, the trim and the report migration, the five newest, so the next down undoes the drop.
  def back_to_drop(home) = home.tap { 5.times { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call } }

  # Undoes the run usage migration and the time migration, the two newest, which keep nothing in a store of the previous release, so the next down undoes the one before them.
  # Undoes the run usage migration, the newest, which removes its version alone, so the next down undoes the one before it.
  def without_usage(home) = home.tap { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call }

  def utc_down(home) = home.tap { 2.times { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call } }

  # A migrated store whose run usage migration, time migration, page migration, trim and report migration went down, so the drop is the newest migration it records.
  def migrated_to_drop = back_to_drop(migrated_previous_home)

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

  # Makes plastic.db refuse every ledger row of the `event`, as a locked or broken plastic.db would.
  def refuse_ledger(home, event)
    SQLite3::Database.open(File.join(home, "plastic.db")) do |database|
      database.execute("CREATE TRIGGER refuse_#{event} BEFORE INSERT ON store_migrations WHEN NEW.event = '#{event}' BEGIN SELECT RAISE(ABORT, 'refused'); END")
    end
  end

  def store_bytes(home) = Dir.glob(alpha_file(home, "*.db")).sort.to_h { |path| [File.basename(path), File.binread(path)] }

  def backup_folders(home) = Dir.glob(alpha_file(home, "backups/*")).select { |path| File.directory?(path) }.map { |path| File.basename(path) }.sort
end
