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

  def old_layout(home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    database_files(home).each { |path| downgrade(path) }
    home
  end

  def database_files(home) = Dir.glob(File.join(home, "{local.db,stores/*/*.db}"))

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

  private

  def downgrade(path)
    with_database(path) do |db|
      db.execute_batch(OLD_INTENTS) if db.get_first_value("SELECT 1 FROM sqlite_master WHERE name = 'intents' AND type = 'table'")
      db.execute("ALTER TABLE locks RENAME COLUMN locked_at TO taken_at") if db.get_first_value("SELECT 1 FROM sqlite_master WHERE name = 'locks' AND type = 'table'")
      db.execute("PRAGMA user_version = 0")
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
