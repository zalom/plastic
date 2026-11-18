# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalStoreReadTest < Plastic::TestCase
  def put(table, row) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(table, row) }

  def store_read = Plastic::Graph::Retrieval::StoreRead.new(store_graphs.databases, origin)

  def test_a_kept_file_reads_its_bytes
    put(:sqlar, { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: SQLite3::Blob.new("\x00\xFF".b), intent_id: "1", sha256: "h" })

    assert_equal "\x00\xFF".b, store_read.kept_file_data("store/1--a/x.bin")
  end

  def test_the_printed_files_of_every_store_database_map_to_their_hash
    put(:printed, { path: "store/index.json", sha256: "a", at: "t" })
    put(:printed, { path: "store/1--a/spec.md", sha256: "b", at: "t" })

    assert_equal({ "store/index.json" => "a", "store/1--a/spec.md" => "b" }, store_read.printed)
  end

  def test_no_legacy_intent_rows_read_from_a_fresh_store
    assert_empty store_read.legacy_intents_data
  end
end
