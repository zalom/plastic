# frozen_string_literal: true

require "tmpdir"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/legacy_table"

class LegacyTableTest < Plastic::TestCase
  LegacyTable = Plastic::Graph::LegacyTable
  VERSION = "20261119000000"
  LATER = "20270101000000"
  FILES = <<~SQL
    CREATE TABLE IF NOT EXISTS main."sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "data" BLOB, "origin_id" TEXT NOT NULL, UNIQUE("name"));
    INSERT INTO sqlar VALUES ('a.md', 420, X'6f6c64', 'o'), ('b.md', 420, NULL, 'o');
  SQL

  def setup
    super
    folder = Dir.mktmpdir("legacy", @home)
    @legacy = File.join(folder, "legacy.db")
    @connection = Plastic::Graph::Database::Connection.open(File.join(folder, "knowledge_graph.db"), attach: { legacy: @legacy })
    @connection.execute_batch(FILES)
  end

  def teardown
    @connection.close
    super
  end

  def table(name = "sqlar", version = VERSION) = LegacyTable.new(@connection, name, version)

  def rows(schema, name) = @connection.execute("SELECT * FROM #{schema}.\"#{name}\" ORDER BY name").map(&:values)

  def columns(schema, name) = @connection.execute("SELECT name, type, \"notnull\", pk FROM pragma_table_info('#{name}', '#{schema}')").map(&:values)

  def legacy_tables = @connection.execute("SELECT name FROM legacy.sqlite_master WHERE type = 'table' ORDER BY name").map { |row| row.fetch("name") }

  def test_a_keep_copies_every_row_into_a_table_named_for_the_version_in_the_old_shape
    count = table.keep

    assert_equal [2, rows("main", "sqlar"), columns("main", "sqlar")], [count, rows("legacy", "sqlar_#{VERSION}"), columns("legacy", "sqlar_#{VERSION}")]
  end

  def test_a_keep_with_a_condition_copies_only_the_rows_it_selects
    table.keep("name IN (SELECT value FROM json_each(?))", ['["a.md"]'])

    assert_equal [["a.md", 420, "old", "o"]], rows("legacy", "sqlar_#{VERSION}")
  end

  def test_a_second_keep_adds_its_rows_and_the_live_row_wins_over_a_kept_row_with_its_key
    table.keep("name = 'a.md'")
    @connection.execute("UPDATE sqlar SET data = X'6e6577' WHERE name = 'a.md'")
    table.keep

    assert_equal [["a.md", 420, "new", "o"], ["b.md", 420, nil, "o"]], rows("legacy", "sqlar_#{VERSION}")
  end

  def test_a_missing_table_keeps_nothing_and_makes_no_legacy_table
    assert_equal [0, []], [table("document_revisions").keep, legacy_tables]
  end

  def test_a_restore_makes_a_dropped_table_again_with_its_rows
    table.keep
    before = [rows("main", "sqlar"), columns("main", "sqlar")]
    @connection.execute("DROP TABLE main.sqlar")
    table.restore

    assert_equal before, [rows("main", "sqlar"), columns("main", "sqlar")]
  end

  def test_a_restore_puts_back_the_removed_rows_and_skips_a_live_row_that_is_the_same
    table.keep
    @connection.execute("DELETE FROM sqlar WHERE name = 'b.md'")

    assert_equal [1, [["a.md", 420, "old", "o"], ["b.md", 420, nil, "o"]]], [table.restore, rows("main", "sqlar")]
  end

  def test_a_restore_over_a_row_that_changed_after_the_keep_raises_changed
    table.keep
    @connection.execute("UPDATE sqlar SET data = X'6e6577' WHERE name = 'a.md'")

    error = assert_raises(LegacyTable::Changed) { table.restore }
    assert_equal "a row of sqlar changed after migration #{VERSION} kept it", error.message
  end

  def test_the_tables_of_a_version_are_the_legacy_tables_named_for_it
    table.keep
    table("sqlar", LATER).keep

    assert_equal [["sqlar"], ["sqlar"]], [LegacyTable.of(@connection, VERSION).map(&:table), LegacyTable.of(@connection, LATER).map(&:table)]
  end

  def test_a_drop_removes_the_legacy_table
    table.keep
    table.drop

    assert_equal [[], false], [legacy_tables, table.kept?]
  end
end
