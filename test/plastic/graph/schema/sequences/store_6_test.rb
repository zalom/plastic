# frozen_string_literal: true

require "digest"
require_relative "../../../../test_helper"

# Store migration 6 is frozen: a digest pins its text. It copies the kept files of references.db into knowledge, and the retire step removes references.db only after each row reads back by name and hash.
class SchemaStore6Test < Plastic::TestCase
  Layout = Plastic::Graph::SchemaStore1::Layout::TEXT
  Sequences = Plastic::Graph::SchemaSequences
  Migration = Plastic::Graph::SchemaStore6
  FILES = { "notes/a.md" => "alpha bytes", "notes/b.bin" => "\x00\x01binary\xFF".b }.freeze

  def setup
    super
    @folder = Dir.mktmpdir
    @knowledge = SQLite3::Database.new(knowledge_path, results_as_hash: true)
    @knowledge.execute_batch(Layout.fetch(:knowledge) + Plastic::Graph::SchemaStore4::TEXT.fetch(:knowledge))
    @knowledge.execute("PRAGMA user_version = 5")
    seed_references
  end

  def knowledge_path = File.join(@folder, "knowledge_graph.db")

  def references_path = File.join(@folder, "references.db")

  def references = SQLite3::Database.new(references_path, results_as_hash: true)

  def seed_references
    database = references
    database.execute_batch(Layout.fetch(:references))
    FILES.each { |name, data| insert_kept(database, name, data) }
    database.execute("INSERT INTO changes (\"table\", \"key\", operation, \"row\", at, origin_id) VALUES ('sqlar', 'notes/a.md', 'put', '{}', 't', 'o')")
    database.execute("INSERT INTO printed (path, sha256, at, origin_id) VALUES ('notes/a.md', 'h', 't', 'o')")
  ensure
    database&.close
  end

  def insert_kept(database, name, data)
    database.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES (?, 420, 1, ?, ?, '1', ?, 'o')", [name, data.bytesize, SQLite3::Blob.new(data), Digest::SHA256.hexdigest(data)])
  end

  def apply(**) = Migration.apply(@knowledge, :knowledge, { knowledge: knowledge_path }, **)

  def kept = @knowledge.execute("SELECT name, data, sha256 FROM sqlar ORDER BY name").to_h { |row| [row["name"], [row["data"].b, row["sha256"]]] }

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal "pending", Digest::SHA256.hexdigest(Migration.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/store_6.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_kept_files_are_copied_with_their_bytes_and_hashes
    apply

    assert_equal FILES.to_h { |name, data| [name, [data, Digest::SHA256.hexdigest(data)]] }, kept
  end

  def test_the_changes_and_printed_rows_are_copied
    apply

    assert_equal [1, 1], [@knowledge.get_first_value("SELECT count(*) FROM changes WHERE \"key\" = 'notes/a.md'"), @knowledge.get_first_value("SELECT count(*) FROM printed WHERE path = 'notes/a.md'")]
  end

  def test_a_store_with_no_references_file_gets_the_empty_table_and_no_error
    File.delete(references_path)
    apply

    assert_equal [0, true], [@knowledge.get_first_value("SELECT count(*) FROM sqlar"), Migration.retire(knowledge_path, references_path)]
  end

  def test_the_retire_step_removes_the_file_only_after_every_row_reads_back
    apply
    Migration.retire(knowledge_path, references_path)

    refute File.exist?(references_path)
  end

  def test_the_retire_step_keeps_the_file_when_a_row_differs_in_knowledge
    apply
    @knowledge.execute("UPDATE sqlar SET sha256 = 'other' WHERE name = 'notes/a.md'")

    assert_raises(Migration::Mismatch) { Migration.retire(knowledge_path, references_path) }
    assert File.exist?(references_path)
  end

  def test_the_retire_step_keeps_the_file_when_a_row_is_missing_in_knowledge
    apply
    @knowledge.execute("DELETE FROM sqlar WHERE name = 'notes/b.bin'")

    assert_raises(Migration::Mismatch) { Migration.retire(knowledge_path, references_path) }
    assert File.exist?(references_path)
  end

  def test_a_stop_after_the_copy_leaves_the_references_file_and_the_rerun_copies_again
    assert_raises(IOError) { @knowledge.transaction(:immediate) { apply(between: -> { raise IOError, "killed" }) } }

    assert_equal [0, true], [@knowledge.get_first_value("SELECT count(*) FROM sqlar"), File.exist?(references_path)]
    @knowledge.transaction(:immediate) { apply }

    assert_equal FILES.keys, kept.keys
  end

  def test_the_other_files_take_no_part
    work = SQLite3::Database.new(":memory:", results_as_hash: true)

    assert_nil Migration.apply(work, :work, {})
  end

  def test_a_connection_that_returns_rows_by_name_runs_the_migration_through_the_runner_sequence
    Sequences.migrate(@knowledge, Sequences::SEQUENCES.fetch(:store).last(1), :knowledge, { knowledge: knowledge_path })

    assert_equal [6, FILES.keys], [@knowledge.get_first_value("PRAGMA user_version"), kept.keys]
  end
end
