# frozen_string_literal: true

require "sqlite3"
require_relative "beta_2_store"
require_relative "schema_versions"

# Turns a throwaway home made by BackupHomes into the layout of an older
# release: each store becomes the beta.2 fixture store, and the home database
# records no migration and has the tables of local.db.
module OldLayoutHomes
  include Beta2Store
  include SchemaVersions

  OLD_HOME_TABLES = <<~SQL
    ALTER TABLE command_runs RENAME TO routine_runs;
    DROP TABLE "settings";
    DROP TABLE "printed";
    CREATE TABLE "locks"("store" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "session_id" TEXT NOT NULL, "mode" TEXT, "taken_at" TEXT, "renewed_at" TEXT, UNIQUE("store", "intent_id"));
    CREATE TABLE "backups"("name" TEXT NOT NULL, "files" INTEGER, "bytes" INTEGER, "sha256" TEXT, "at" TEXT, "session_id" TEXT, UNIQUE("name"));
  SQL

  def old_layout(home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    Dir.glob(File.join(home, "{local.db,plastic.db}")).each { |path| downgrade(path) }
    old_stores(home)
    File.rename(File.join(home, "plastic.db"), File.join(home, "local.db")) if File.exist?(File.join(home, "plastic.db"))
    home
  end

  # The live database files of the home. The legacy.db a migration makes holds only the rows it removed, and a new home has none.
  def database_files(home) = Dir.glob(File.join(home, "{local.db,plastic.db,stores/*/*.db}")).reject { |path| File.basename(path) == "legacy.db" }

  # The versions each database file records, nil for a file with no schema_migrations table.
  def recorded_by_file(home) = database_files(home).to_h { |path| [path, recorded_versions(path)] }

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

  def layouts(home) = database_files(home).to_h { |path| [path.delete_prefix(home), layout_of(path)] }

  def file_bytes(home) = database_files(home).to_h { |path| [path, File.binread(path)] }

  private

  def downgrade(path)
    with_database(path) do |db|
      db.execute_batch(OLD_HOME_TABLES) if db.get_first_value("SELECT 1 FROM sqlite_master WHERE name = 'command_runs' AND type = 'table'")
      db.execute("DROP TABLE IF EXISTS schema_migrations")
      db.execute("PRAGMA user_version = 0")
    end
  end

  def old_stores(home)
    origin = Plastic::Graph::Origin.new(home).id
    Dir.glob(File.join(home, "stores", "*")).each do |store|
      Dir.glob(File.join(store, "*.db*")).each { |file| File.delete(file) }
      Beta2Store::FILES.each { |file, name| build_beta_2_file(File.join(store, file), name, origin, true) }
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
