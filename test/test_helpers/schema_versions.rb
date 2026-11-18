# frozen_string_literal: true

require "sqlite3"

# Reads the migrations a database file records in its schema_migrations table, and fakes a file that a newer
# release wrote by recording a version this code does not know.
module SchemaVersions
  UNKNOWN = "20991231000000"
  TABLE = "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)"

  # The recorded versions in ascending order, or nil when the file has no schema_migrations table.
  def recorded_versions(path)
    SQLite3::Database.open(path, readonly: true) do |database|
      next nil unless database.get_first_value("SELECT 1 FROM sqlite_master WHERE name = 'schema_migrations'")

      database.execute("SELECT version FROM schema_migrations ORDER BY version").flatten
    end
  end

  def record_versions(path, versions)
    SQLite3::Database.open(path) do |database|
      database.execute(TABLE)
      versions.each { |version| database.execute("INSERT OR IGNORE INTO schema_migrations (version) VALUES (?)", [version]) }
    end
  end

  def record_unknown_version(path, version = UNKNOWN) = record_versions(path, [version])
end
