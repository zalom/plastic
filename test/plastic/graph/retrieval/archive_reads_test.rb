# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalArchiveReadsTest < Plastic::TestCase
  def setup
    super
    @intent = open_intent
  end

  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def keep(name, bytes)
    put(:references, :sqlar, { name:, mode: 0o100644, mtime: 0, sz: bytes.bytesize, data: Plastic::Graph::SQL::Bytes.new(bytes), intent_id: "1", sha256: "h" })
  end

  def test_a_reference_into_an_archived_intent_is_archived
    put(:work, :archives, { intent_id: "1", at: STAMP })

    assert retrieval.archived_reference?(retrieval.reference("1", @intent.file).fetch(:uri))
  end

  def test_a_reference_into_a_live_intent_is_not_archived
    refute retrieval.archived_reference?(retrieval.reference("1", @intent.file).fetch(:uri))
  end

  def test_a_reference_to_no_document_is_refused
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.archived_reference?("plastic://global/1/none.md") }
  end

  def test_the_kept_files_of_one_intent_read_by_name
    keep("store/1--alpha/x.bin", "\x00".b)

    assert_equal ["store/1--alpha/x.bin"], retrieval.kept_files("1").map(&:name)
  end

  def test_a_kept_file_reads_its_bytes_by_name
    keep("store/1--alpha/x.bin", "\x00\xFF".b)

    assert_equal "\x00\xFF".b, retrieval.kept_file_data("store/1--alpha/x.bin")
  end
end
