# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalReferenceBackfillTest < Plastic::TestCase
  Backfill = Plastic::Graph::Retrieval::ReferenceBackfill

  def setup
    super
    @writes = 0
  end

  def knowledge = store_graphs.databases[:knowledge]

  def backfill = Backfill.new(store_graphs.databases, origin, after_write: -> { @writes += 1 }).call

  def keep(name, bytes)
    row = { name:, mode: 0o100644, mtime: 0, sz: bytes.bytesize, data: Plastic::Graph::SQL::Bytes.new(bytes), intent_id: "1", sha256: "h" }
    store_graphs.databases[:references].transaction { |batch| batch.put(:sqlar, row) }
  end

  def heads = knowledge.rows("SELECT path FROM document_heads ORDER BY path").map { |row| row.fetch("path") }

  def test_a_missing_database_file_is_not_complete
    refute Backfill.complete?(File.join(@home, "none.db"), origin)
  end

  def test_a_store_is_not_complete_before_the_backfill
    store_graphs

    refute Backfill.complete?(knowledge.path, origin)
  end

  def test_the_backfill_marks_the_store_complete_for_its_origin
    backfill

    assert_equal [true, false], [Backfill.complete?(knowledge.path, origin), Backfill.complete?(knowledge.path, "beef")]
  end

  def test_a_text_kept_file_gets_a_document_head
    keep("store/1--alpha/notes.txt", "Kept notes\n")
    backfill

    assert_equal [["notes.txt"], 1], [heads, @writes]
  end

  def test_a_binary_kept_file_is_left_out
    keep("store/1--alpha/image.png", "\x89PNG\x00".b)
    backfill

    assert_empty heads
  end

  def test_a_document_that_already_has_a_head_is_not_written_again
    open_intent
    backfill

    assert_equal 0, @writes
  end

  def test_a_complete_store_is_not_scanned_again
    backfill
    keep("store/1--alpha/notes.txt", "Kept notes\n")
    backfill

    assert_empty heads
  end
end
