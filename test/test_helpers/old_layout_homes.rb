# frozen_string_literal: true

require "sqlite3"

# Turns a throwaway home made by BackupHomes into the layout of an older
# release: every database unstamped, the intents table with the old word for
# work under way, and the locks table with the old time column.
module OldLayoutHomes
  OLD_INTENTS = <<~SQL
    DROP TABLE intents;
    CREATE TABLE "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT,
      "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT,
      "status" TEXT NOT NULL CHECK(status IN ('open', 'active', 'parked', 'future', 'done', 'abandoned')),
      "disposition" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
    INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('7', 'o-1', 'seven', 'Seven', 'active');
  SQL

  OLD_HOME_TABLES = <<~SQL
    ALTER TABLE command_runs RENAME TO routine_runs;
    CREATE TABLE "backups"("name" TEXT NOT NULL, "files" INTEGER, "bytes" INTEGER, "sha256" TEXT, "at" TEXT, "session_id" TEXT, UNIQUE("name"));
  SQL

  def old_layout(home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    database_files(home).each { |path| downgrade(path) }
    restore_old_references(home)
    File.rename(File.join(home, "plastic.db"), File.join(home, "local.db")) if File.exist?(File.join(home, "plastic.db"))
    home
  end

  def database_files(home) = Dir.glob(File.join(home, "{local.db,plastic.db,stores/*/*.db}"))

  def user_versions(home) = database_files(home).to_h { |path| [path, read_value(path, "PRAGMA user_version")] }

  def layout_of(path)
    rows = with_database(path, readonly: true) { |db| db.execute("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name") }
    rows.map { |type, name, sql| [type, name, sql.to_s.gsub(/\s+/, " ").strip] }
  end

  def row_digest(path)
    with_database(path, readonly: true) do |db|
      tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").flatten
      Digest::SHA256.hexdigest(tables.map { |table| [table, db.execute("SELECT * FROM \"#{table}\"").map(&:inspect).sort] }.inspect)
    end
  end

  def file_bytes(home) = database_files(home).to_h { |path| [path, File.binread(path)] }

  MOVED_TABLES = %w[intents clusters completions approvals verdicts archives archive_entries].freeze
  LAYOUT = Plastic::Graph::SchemaStore1::Layout::TEXT

  private

  def downgrade(path)
    with_database(path) do |db|
      restore_old_tables(db, File.basename(path))
      db.execute("ALTER TABLE locks RENAME COLUMN locked_at TO taken_at") if db.get_first_value("SELECT 1 FROM sqlite_master WHERE name = 'locks' AND type = 'table'")
      db.execute_batch(OLD_HOME_TABLES) if db.get_first_value("SELECT 1 FROM sqlite_master WHERE name = 'command_runs' AND type = 'table'")
      db.execute("PRAGMA user_version = 0")
    end
  end

  def restore_old_tables(db, name)
    case name
    when "work_graph.db" then db.execute_batch(LAYOUT.fetch(:work) + OLD_INTENTS)
    when "knowledge_graph.db" then restore_old_knowledge(db)
    end
  end

  def restore_old_knowledge(db)
    MOVED_TABLES.each { |table| db.execute("DROP TABLE IF EXISTS \"#{table}\"") }
    db.execute_batch(LAYOUT.fetch(:knowledge))
  end

  def restore_old_references(home)
    Dir.glob(File.join(home, "stores", "*")).each do |store|
      FileUtils.rm_f(File.join(store, "retrieval_graph.db"))
      with_database(File.join(store, "references.db")) { |db| db.execute_batch(LAYOUT.fetch(:references)) }
    end
  end

  def read_value(path, sql)
    with_database(path, readonly: true) { |db| db.get_first_value(sql) }
  rescue SQLite3::NotADatabaseException
    :unreadable
  end

  def with_database(path, readonly: false)
    db = SQLite3::Database.new(path, readonly:)
    yield db
  ensure
    db&.close
  end
end
