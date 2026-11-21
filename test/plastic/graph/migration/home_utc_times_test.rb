# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaHomeUtcTimesTest < Plastic::TestCase
  include BackupHomes

  UTC = "20261121090000"
  NOW = Time.utc(2026, 11, 21, 12, 0, 0)
  ROWS = <<~SQL
    INSERT INTO sessions (session_id, started_at, last_turn_at, ended_at) VALUES ('s-9', '2026-10-05T10:00:00+02:00', '2026-10-05T11:00:00+02:00', NULL);
    INSERT INTO command_runs (store, tool, subject, at, finished, facts, started_at, updated_at)
      VALUES ('alpha', 'intent end', '9', 'judged', '[]', '{}', '2026-10-05T10:00:00+02:00', '2026-10-05T03:00:00-05:00');
    INSERT INTO chat_messages (session_id, role, at, text) VALUES ('s-9', 'user', '2026-10-05T10:00:00+02:00', 'hi');
    INSERT INTO printed (path, sha256, at, origin_id) VALUES ('9--a/spec.md', 'sha', '2026-10-05', 'o');
    INSERT INTO sessions (session_id, started_at) VALUES ('s-8', '2026-10-05T25:00:00+02:00');
    DELETE FROM schema_migrations WHERE version = '#{UTC}';
  SQL

  def plastic_db(home) = File.join(home, "plastic.db")

  def rows(home, sql) = SQLite3::Database.new(plastic_db(home), readonly: true).execute(sql)

  def previous_home
    fresh_home.tap do |home|
      Plastic::Graph::Database::ConnectionPool.release(home)
      SQLite3::Database.open(plastic_db(home)) { |database| database.execute_batch(ROWS) }
    end
  end

  def migrate(home) = Plastic::Graph::SchemaRunner.new(home:, now: NOW, selection: Plastic::Graph::Knowledge::SyncSelection.none).call

  def migrated = previous_home.tap { |home| migrate(home) }

  def test_the_home_migration_writes_every_time_of_plastic_db_with_an_offset_in_utc
    home = migrated

    assert_equal [[["2026-10-05T08:00:00Z", "2026-10-05T09:00:00Z", nil]], [["judged", "2026-10-05T08:00:00Z", "2026-10-05T08:00:00Z"]], [["2026-10-05T08:00:00Z"]], [["2026-10-05"]]],
      [rows(home, "SELECT started_at, last_turn_at, ended_at FROM sessions WHERE session_id = 's-9'"),
        rows(home, "SELECT at, started_at, updated_at FROM command_runs WHERE subject = '9'"),
        rows(home, "SELECT at FROM chat_messages WHERE session_id = 's-9'"), rows(home, "SELECT at FROM printed WHERE path = '9--a/spec.md'")]
  end

  def test_the_home_migration_leaves_a_time_it_cannot_read_as_it_was
    assert_equal [["2026-10-05T25:00:00+02:00"]], rows(migrated, "SELECT started_at FROM sessions WHERE session_id = 's-8'")
  end

  def test_the_home_migration_names_each_time_it_cannot_read
    assert_includes migrate(previous_home).notes, "migrate: plastic.db left 1 unreadable time unchanged: main.sessions.started_at 2026-10-05T25:00:00+02:00"
  end

  def test_the_home_records_the_migration
    assert_includes rows(migrated, "SELECT version FROM schema_migrations").flatten, UTC
  end
end
