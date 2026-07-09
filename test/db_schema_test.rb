require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "sqlite3"

require_relative "../scripts/lib/db"

# Hermetic unit tests for Plastic::DB::Schema (intent 41, ACTION_2): the
# Rails-shaped, dialect-clean table set, idempotent ensure!, and the
# schema_meta/format_version cold-rebuild gate. All against a Dir.mktmpdir
# store; Plastic::DB.connect wires Schema.ensure! in by default.
class DbSchemaTest < Minitest::Test
  TABLES = %w[
    intents edges savepoint_events lock_leases sessions
    roadmaps roadmap_entries schema_meta
  ].freeze

  def setup
    @store_home = Dir.mktmpdir("plastic-db-schema-store")
    @conn = Plastic::DB.connect(@store_home)
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def test_all_tables_present
    refute_nil @conn
    existing = @conn.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
    TABLES.each { |t| assert_includes existing, t }
  end

  def test_rails_shape
    TABLES.each do |table|
      columns = @conn.execute("PRAGMA table_info(#{table})")
      # columns: [cid, name, type, notnull, dflt_value, pk]
      id_col = columns.find { |c| c[1] == "id" }
      refute_nil id_col, "#{table} is missing an id column"
      assert_equal "INTEGER", id_col[2], "#{table}.id must be INTEGER"
      assert_equal 1, id_col[5], "#{table}.id must be the PRIMARY KEY"

      names = columns.map { |c| c[1] }
      assert_includes names, "created_at", "#{table} is missing created_at"
      assert_includes names, "updated_at", "#{table} is missing updated_at"
    end
  end

  def test_dialect_clean
    ddl = @conn.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL").flatten.join("\n")

    refute_match(/\bSTRICT\b/i, ddl)
    refute_match(/\bWITHOUT\s+ROWID\b/i, ddl)
    refute_match(/\bvirtual\s+table\b/i, ddl)
    refute_match(/\bUSING\s+vec/i, ddl)

    type_tokens = ddl.scan(/\b(INTEGER|TEXT|REAL|BLOB|NUMERIC|VARCHAR|BOOLEAN|DATE|DATETIME)\b/i).flatten.map(&:upcase)
    disallowed = type_tokens - %w[INTEGER TEXT REAL]
    assert_empty disallowed, "dialect-clean schema must use only INTEGER/TEXT/REAL column types"
  end

  def test_lease_unique_live_holder
    now = "2026-07-09T00:00:00Z"
    insert_lease = lambda do |released_at|
      @conn.execute(
        "INSERT INTO lock_leases (intent_id, artifact, owner_session, host, acquired_at, expires_at, released_at, created_at, updated_at) " \
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["41", "checklist.md", "session-a", "host-a", now, now, released_at, now, now]
      )
    end

    insert_lease.call(nil)
    assert_raises(SQLite3::ConstraintException) { insert_lease.call(nil) }

    # A released row does not block a new live one.
    @conn.execute("UPDATE lock_leases SET released_at = ? WHERE intent_id = ? AND artifact = ?", [now, "41", "checklist.md"])
    insert_lease.call(nil)
  end

  def test_ensure_is_idempotent
    Plastic::DB::Schema.ensure!(@conn)
    Plastic::DB::Schema.ensure!(@conn)

    tables = @conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").flatten
    assert_equal tables.sort, tables.uniq.sort

    count = @conn.execute("SELECT COUNT(*) FROM schema_meta").first.first
    assert_equal 1, count
  end

  def test_schema_meta_single_row_and_format_version
    rows = @conn.execute("SELECT COUNT(*) FROM schema_meta")
    assert_equal 1, rows.first.first

    stored_version = @conn.execute("SELECT format_version FROM schema_meta WHERE id = 1").first.first
    assert_equal Plastic::DB::Schema::FORMAT_VERSION, stored_version
  end

  def test_format_version_bump_flags_cold_rebuild
    refute Plastic::DB::Schema.rebuild_needed?(@conn, code_version: Plastic::DB::Schema::FORMAT_VERSION)
    assert Plastic::DB::Schema.rebuild_needed?(@conn, code_version: Plastic::DB::Schema::FORMAT_VERSION + 1)
  end
end
