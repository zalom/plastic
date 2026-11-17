# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../test_helpers/references_pair"

# The copy of store migration 6 holds rows by list or by name, with and without sibling paths and tables, and refuses a copy that differs.
class SchemaStore6CopyTest < Plastic::TestCase
  include ReferencesPair

  def test_a_changes_copy_that_differs_from_references_raises
    @knowledge.execute("CREATE TRIGGER alter_copy AFTER INSERT ON changes BEGIN UPDATE changes SET at = 'altered' WHERE seq = new.seq; END")

    assert_raises(Migration::Mismatch) { apply }
  end

  def test_a_connection_that_returns_rows_as_lists_copies_the_same_rows
    @knowledge.results_as_hash = false
    Migration.apply(@knowledge, :knowledge, { knowledge: knowledge_path })

    assert_equal FILES.keys, @knowledge.execute("SELECT name FROM sqlar ORDER BY name").flatten
  end

  def test_a_knowledge_file_with_no_sibling_paths_gets_the_table_and_copies_nothing
    Migration.apply(@knowledge, :knowledge)

    assert_equal 0, @knowledge.get_first_value("SELECT count(*) FROM sqlar")
  end

  def test_a_references_file_with_only_the_printed_table_copies_that_table
    File.delete(references_path)
    database = references
    database.execute("CREATE TABLE printed (path TEXT NOT NULL, sha256 TEXT NOT NULL, at TEXT NOT NULL, origin_id TEXT NOT NULL, UNIQUE(path, origin_id))")
    database.execute("INSERT INTO printed (path, sha256, at, origin_id) VALUES ('p.md', 'h', 't', 'o')")
    database.close
    apply

    assert_equal [0, 1], [@knowledge.get_first_value("SELECT count(*) FROM sqlar"), @knowledge.get_first_value("SELECT count(*) FROM printed WHERE path = 'p.md'")]
  end

  def test_a_sqlar_copy_that_differs_from_references_raises
    @knowledge.execute_batch(Migration::TEXT)
    @knowledge.execute("CREATE TRIGGER alter_copy AFTER INSERT ON sqlar BEGIN UPDATE sqlar SET sha256 = 'altered' WHERE name = new.name; END")

    assert_raises(Migration::Mismatch) { apply }
  end
end
