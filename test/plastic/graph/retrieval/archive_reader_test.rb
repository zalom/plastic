# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalArchiveReaderTest < Plastic::TestCase
  def archive(**row) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(:archives, { intent_id: "1", at: STAMP, **row }) }

  def reader = Plastic::Graph::Retrieval::ArchiveReader.new(store_graphs.databases, origin)

  def test_an_intent_with_an_archive_row_is_archived
    archive

    assert reader.archived?("1")
  end

  def test_an_intent_with_no_archive_row_is_not_archived
    refute reader.archived?("1")
  end

  def test_a_restored_intent_is_not_archived
    archive(restored_at: STAMP)

    refute reader.archived?("1")
  end

  def test_an_archive_row_of_another_origin_does_not_count
    archive(origin_id: "beef")

    refute reader.archived?("1")
  end

  def keep(name, bytes)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:sqlar, { name:, mode: 0o100644, mtime: 0, sz: bytes.bytesize, data: SQLite3::Blob.new(bytes), intent_id: "1", sha256: "h" })
    end
  end

  def test_the_kept_files_of_one_intent_read_by_name
    keep("store/1--alpha/x.bin", "\x00".b)

    assert_equal ["store/1--alpha/x.bin"], reader.kept_files("1").map(&:name)
  end

  def test_the_archive_rows_of_one_intent_read
    archive

    assert_equal ["1"], reader.rows("1").map(&:intent_id)
  end
end
