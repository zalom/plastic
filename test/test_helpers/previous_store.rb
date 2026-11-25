# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require "fileutils"
require_relative "../../lib/plastic/graph/migration/migration_down"

# A throwaway home whose registered store alpha the previous release wrote: it records every version before the drop
# of document_revisions, holds a row there, has the column supersedes on its rulings, and keeps in sqlar a file that only its row holds. `migrated_previous_home`
# runs the migrations on it, which keep the earlier revision in legacy.db and print the file back.
module PreviousStore
  DROP = "20261119000000"
  REPORTS = "20261119180000"
  TRIM = "20261119190000"
  PAGES = "20261120090000"
  UTC = "20261121090000"
  USAGE = "20261123090000"
  NODES = "20261123100000"
  NEEDS = "20261123120000"
  DRIVERS = "20261123130000"
  DEADLINE = "20261123154000"
  INPUTS = "20261123170000"
  EMPTY_ROADMAPS = "20261124090000"
  LEFTOVERS = "20261124120000"
  MISTAKES = "20261124150000"
  DRIVER_MODE = "20261124173000"
  DRIVER_AGENT = "20261124200000"
  WORK_LOG_TEXT = "20261124210000"
  OWN_IDS = "20261124233000"
  PLACEHOLDERS = "20261125100000"
  FOLDS = "20261125110000"
  OWNER_TIME = "INSERT INTO intents (intent_id, origin_id, slug, title, status, opened_at, updated_at) VALUES ('91', 'o', '91--a', 'A', 'open', '2026-10-05', '2026-10-05T10:00:00+02:00')"
  OWNER_KEPT = "changed_values_#{UTC}"
  USAGE_COLUMNS = %w[harness worker_session usage_note model input_tokens output_tokens cache_read_tokens cache_write_tokens cost_usd].freeze
  NODE_COLUMNS = %w[judge verdict].freeze
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
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| PreviousStore.older_knowledge(database) }
    older_work_layout(home)
  end

  NEWER = [DROP, REPORTS, TRIM, PAGES, UTC, USAGE, NODES, NEEDS, DRIVERS, DEADLINE, INPUTS, EMPTY_ROADMAPS, LEFTOVERS, MISTAKES, DRIVER_MODE, DRIVER_AGENT,
    WORK_LOG_TEXT, OWN_IDS, PLACEHOLDERS, FOLDS].freeze

  # The knowledge file of the previous release: a row of document_revisions, none of the newer versions, and the column supersedes on its rulings.
  def self.older_knowledge(database)
    database.execute_batch(REVISIONS)
    database.execute("DELETE FROM schema_migrations WHERE version IN (#{(["?"] * NEWER.size).join(", ")})", NEWER)
    database.execute("ALTER TABLE rulings ADD COLUMN supersedes TEXT")
  end

  # The work file as the release before the column migrations wrote it: no run usage columns, the node columns judge and verdict, no node deadline, the node input column in place of the table node_inputs, and no driver mode, no driver agent and no old and new text on a work log line.
  def older_work_layout(home)
    SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| PreviousStore.older_work_layout(database) }
    home
  end

  def self.older_work_layout(database)
    USAGE_COLUMNS.each { |column| database.execute("ALTER TABLE runs DROP COLUMN #{column}") }
    NODE_COLUMNS.each { |column| database.execute("ALTER TABLE nodes ADD COLUMN #{column} TEXT") }
    database.execute("ALTER TABLE nodes DROP COLUMN deadline")
    database.execute("DROP TABLE node_inputs")
    database.execute("ALTER TABLE nodes ADD COLUMN input TEXT")
    database.execute("ALTER TABLE drivers DROP COLUMN mode")
    database.execute("ALTER TABLE drivers DROP COLUMN agent")
    %w[old_text new_text].each { |column| database.execute("ALTER TABLE work_log DROP COLUMN #{column}") }
  end

  # A store of the previous release whose intent holds a time with an offset. The time migration keeps its old text in legacy.db, the owner's data, so the migrated store has a legacy.db.
  def previous_home_with_times = previous_home.tap { |home| SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute(OWNER_TIME) } }

  def migrated_previous_home = previous_home.tap { |home| migrate_store(home) }

  def migrate_store(home, now: MIGRATED_AT)
    Plastic::Graph::SchemaRunner.new(home:, now:, selection: Plastic::Graph::Knowledge::SyncSelection.none).call.tap { forget(home) }
  end

  # Runs the migrations of the store but the versions `skipped`, which stay pending after the run, as in a store of
  # an earlier release that shipped without them.
  def migrate_without(home, skipped, now: MIGRATED_AT)
    path = alpha_file(home, "knowledge_graph.db")
    SQLite3::Database.open(path) { |database| skipped.each { |version| database.execute("INSERT INTO schema_migrations (version) VALUES (?)", [version]) } }
    migrate_store(home, now:).tap do
      SQLite3::Database.open(path) { |database| skipped.each { |version| database.execute("DELETE FROM schema_migrations WHERE version = ?", [version]) } }
    end
  end

  # Undoes the fold migration, the placeholder migration, the ruling own id migration, the work log text migration, the driver agent migration, the driver mode migration, the leftover work tables migration, the empty roadmap tables migration, the node inputs migration, the deadline migration, the driver migration, the roadmap migration, the node columns migration, the run usage migration, the time migration, the page migration, the trim and the report migration, so the next down undoes the drop.
  def back_to_drop(home) = home.tap { 19.times { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call } }

  # Undoes the fold migration, the placeholder migration, the ruling own id migration, the work log text migration, the driver agent migration, the driver mode migration, the leftover work tables migration, the empty roadmap tables migration, the node inputs migration, the deadline migration, the driver migration, the roadmap migration, the node columns migration and the run usage migration, which remove their versions alone, so the next down undoes the one before them.
  def without_usage(home) = home.tap { 15.times { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call } }

  # Undoes the newest migrations of a store that ran only some, which keep nothing in a store of the previous release, so the next down undoes the one before them.
  def utc_down(home) = home.tap { 16.times { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call } }

  # A migrated store whose node inputs migration, deadline migration, driver migration, node columns migration, run usage migration, time migration, page migration, trim and report migration went down, so the drop is the newest migration it records.
  def migrated_previous_home_with_times = previous_home_with_times.tap { |home| migrate_store(home) }

  # A migrated store of the owner's data, taken back to the UTC migration, so the next down puts back the rows it kept.
  def migrated_to_owner = without_usage(migrated_previous_home_with_times)

  def forget(home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    Plastic::Graph::Database::ConnectionPool.created.clear
  end

  def alpha_file(home, name) = File.join(home, "stores", "alpha", name)

  def alpha_rows(home, name, sql)
    SQLite3::Database.open(alpha_file(home, name), readonly: true) { |database| database.execute(sql) }
  end

  def recorded(home) = alpha_rows(home, "knowledge_graph.db", "SELECT version FROM schema_migrations ORDER BY version").flatten

  # The tables of legacy.db, none when the store has no legacy.db.
  def legacy_tables(home) = File.exist?(alpha_file(home, "legacy.db")) ? alpha_rows(home, "legacy.db", "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").flatten : []

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
