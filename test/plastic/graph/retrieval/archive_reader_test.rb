# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalArchiveReaderTest < Plastic::TestCase
  def archive(**row) = store_graphs.databases[:work].transaction { |batch| batch.put(:archives, { intent_id: "1", at: STAMP, **row }) }

  def reader = Plastic::Graph::Retrieval::ArchiveReader.new(store_graphs.databases[:work], origin)

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
end
