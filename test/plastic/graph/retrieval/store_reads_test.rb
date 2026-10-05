# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalStoreReadsTest < Plastic::TestCase
  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def test_the_retrieval_graph_reads_the_printed_files
    put(:work, :printed, { path: "store/index.json", sha256: "a", at: "t" })

    assert_equal({ "store/index.json" => "a" }, retrieval.printed)
  end

  def test_the_retrieval_graph_reads_the_backups_and_their_flags
    put(:home, :backups, { name: "a.tar.gz", files: 1, bytes: 1, sha256: "x", at: STAMP })
    read = retrieval

    assert_equal [["a.tar.gz", "missing"]], read.backups.map { |backup| [backup.name, read.backup_flag(backup)] }
  end
end
