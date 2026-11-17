# frozen_string_literal: true

require "digest"
require_relative "../../../../test_helper"
require_relative "../../../../test_helpers/references_pair"

# Store migration 6 is frozen: a digest pins its text. It copies the kept files of references.db into knowledge, and the retire step removes references.db only after each row reads back by name and hash.
class SchemaStore6Test < Plastic::TestCase
  include ReferencesPair

  Sequences = Plastic::Graph::SchemaSequences

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal "cea333abf2a4e25cc1fc09ec1a2a6f9326456cc1e4d8e7e6eeeaa7fcc66de19d", Digest::SHA256.hexdigest(Migration.texts.join("\n--\n"))
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

    refute_path_exists references_path
  end

  def test_the_retire_step_keeps_the_file_when_a_row_differs_in_knowledge
    apply
    @knowledge.execute("UPDATE sqlar SET sha256 = 'other' WHERE name = 'notes/a.md'")

    assert_raises(Migration::Mismatch) { Migration.retire(knowledge_path, references_path) }
    assert_path_exists references_path
  end

  def test_the_retire_step_keeps_the_file_when_a_row_is_missing_in_knowledge
    apply
    @knowledge.execute("DELETE FROM sqlar WHERE name = 'notes/b.bin'")

    assert_raises(Migration::Mismatch) { Migration.retire(knowledge_path, references_path) }
    assert_path_exists references_path
  end

  def test_a_stop_after_the_copy_leaves_the_references_file_and_the_rerun_copies_again
    assert_raises(IOError) { @knowledge.transaction(:immediate) { apply(between: -> { raise IOError, "killed" }) } }

    assert_equal [5, true], [@knowledge.get_first_value("PRAGMA user_version"), File.exist?(references_path)]
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
