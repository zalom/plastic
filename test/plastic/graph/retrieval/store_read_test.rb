# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalStoreReadTest < Plastic::TestCase
  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def store_read = Plastic::Graph::Retrieval::StoreRead.new(store_graphs.databases)

  def backup(name, sha256: "x") = put(:local, :backups, { name:, files: 1, bytes: 1, sha256:, at: name })

  def test_a_kept_file_reads_its_bytes
    put(:references, :sqlar, { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: Plastic::Graph::SQL::Bytes.new("\x00\xFF".b), intent_id: "1", sha256: "h" })

    assert_equal "\x00\xFF".b, store_read.kept_file_data("store/1--a/x.bin")
  end

  def test_the_printed_files_of_every_store_database_map_to_their_hash
    put(:work, :printed, { path: "store/index.json", sha256: "a", at: "t" })
    put(:knowledge, :printed, { path: "store/1--a/spec.md", sha256: "b", at: "t" })

    assert_equal({ "store/index.json" => "a", "store/1--a/spec.md" => "b" }, store_read.printed)
  end

  def test_backups_read_in_time_order
    backup("b-backup")
    backup("a-backup")

    assert_equal %w[a-backup b-backup], store_read.backups.map(&:name)
  end
end
