# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalReferenceBackfillTest < Plastic::TestCase
  Backfill = Plastic::Graph::Retrieval::ReferenceBackfill

  def setup
    super
    @writes = 0
  end

  def graphs
    @graphs ||= begin
      FileUtils.mkdir_p(File.join(@plastic_home, "stores", "backfill"))
      Plastic::Graph.open(home: @plastic_home, store: "backfill")
    end
  end

  def knowledge = graphs.databases[:knowledge]

  def backfill = Backfill.new(graphs.databases, origin, after_write: -> { @writes += 1 }).call

  def keep(name, bytes)
    row = { name:, mode: 0o100644, mtime: 0, sz: bytes.bytesize, data: SQLite3::Blob.new(bytes), intent_id: "1", sha256: "h" }
    graphs.databases[:references].transaction { |batch| batch.put(:sqlar, row) }
  end

  def heads = knowledge.rows("SELECT path FROM document_heads ORDER BY path").map { |row| row.fetch("path") }

  def test_a_complete_global_store_leaves_this_store_incomplete
    Backfill.new(Plastic::Graph.open(home: @plastic_home, store: "global").databases, origin).call

    refute Backfill.complete?(knowledge.path, origin)
  end

  def test_a_missing_database_file_is_not_complete
    refute Backfill.complete?(File.join(@home, "none.db"), origin)
  end

  def test_a_store_is_not_complete_before_the_backfill
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
    work = graphs.work
    work.print_intent(work.write_intent(title: "Alpha").intent_id)
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

class RetrievalBackfillOriginTest < Plastic::TestCase
  def test_one_origin_completion_does_not_complete_another_origin
    first = retrieval.origin_id
    second = "second-origin"
    write_document(first, "first.md", "first text")
    write_document(second, "second.md", "second text")

    complete(first)

    assert_first_does_not_complete_second(first, second)
    complete(second)

    assert_second_completion
  end

  def test_completion_probe_does_not_create_an_absent_database
    path = File.join(@home, "missing", "knowledge_graph.db")

    refute Plastic::Graph::Retrieval::ReferenceBackfill.complete?(path, origin)
    refute_path_exists File.dirname(path)
  end

  def test_completion_probe_treats_an_unreadable_database_file_as_incomplete
    path = File.join(@home, "not-a-database")
    File.binwrite(path, "not sqlite")

    refute Plastic::Graph::Retrieval::ReferenceBackfill.complete?(path, origin)
  end

  private

  def knowledge = store_graphs.databases.fetch(:knowledge)
  def complete(origin) = Plastic::Graph::Retrieval::ReferenceBackfill.new(store_graphs.databases, origin).call

  def assert_first_does_not_complete_second(first, second)
    assert Plastic::Graph::Retrieval::ReferenceBackfill.complete?(knowledge.path, first)
    refute Plastic::Graph::Retrieval::ReferenceBackfill.complete?(knowledge.path, second)
  end

  def assert_second_completion
    assert Plastic::Graph::Retrieval::ReferenceBackfill.complete?(knowledge.path, "second-origin")
    assert_equal ["first.md", "second.md"], knowledge.rows("SELECT path FROM document_heads ORDER BY path").map { |row| row.fetch("path") }
  end

  def write_document(origin, path, body)
    knowledge.transaction do |batch|
      batch.add("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', :path, :body, 'then', :origin)", path:, body:, origin:)
    end
  end
end
