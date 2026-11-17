# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupRestorerVersionTest < Plastic::TestCase
  include BackupHomes

  STAMP = "20260101100000"

  def restorer(home)
    local_db = Plastic::Graph.create(home:, store: "alpha").databases.fetch(:local)
    target = Plastic::Graph::Backup::Target.new(local_db, File.join(home, "stores", "alpha"), "alpha", nil)
    Plastic::Graph::Backup::Restorer.new(target, Plastic::Graph.open(home:, store: "alpha").retrieval, now: at(2026, 6, 1, 12, 0, 0))
  end

  def damage(home)
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    File.delete(store_file(home, "references"))
    File.write(store_file(home, "knowledge_graph"), "not a database")
  end

  def test_a_partial_restore_ignores_a_missing_live_file_and_an_unreadable_one_when_it_reads_the_store_version
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    ready = restorer(home)
    damage(home)

    assert_nil ready.refusal(STAMP, databases: %w[work_graph])
  end
end
