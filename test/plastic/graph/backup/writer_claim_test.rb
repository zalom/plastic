# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupWriterClaimTest < Plastic::TestCase
  include BackupHomes

  Writer = Plastic::Graph::Backup::Writer
  FIRST = Time.utc(2026, 1, 1, 10, 0, 0)

  def root(home) = File.join(home, "stores", "alpha")

  def automatic(home, now) = Writer.new(root(home), "alpha", now:, automatic: true, reason: "sync up").call

  def claim(home, name)
    FileUtils.mkdir_p(backups_dir(home))
    Dir.mkdir(File.join(backups_dir(home), name))
  end

  def test_a_session_that_finds_a_claim_one_second_old_takes_no_backup
    home = fresh_home
    claim(home, "20260101100000")
    add_intent(home)

    assert_nil automatic(home, FIRST + 1)
    assert_equal ["20260101100000"], folder_names(home)
  end

  def test_a_claim_older_than_a_few_minutes_does_not_stop_a_session
    home = fresh_home
    claim(home, "20260101100000")
    add_intent(home)

    refute_nil automatic(home, FIRST + 600)
    assert_equal %w[20260101100000 20260101101000], folder_names(home)
  end

  def test_a_failed_source_check_removes_the_claim
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(root(home))
    File.write(store_file(home, "work_graph"), "not a database")

    assert_raises(Writer::Error) { automatic(home, FIRST) }
    assert_empty folder_names(home)
  end

  def test_an_unchanged_store_removes_its_claim_and_keeps_the_newest_backup
    home = fresh_home
    backup_at(home, FIRST)

    assert_nil automatic(home, FIRST + 3600)
    assert_equal ["20260101100000"], folder_names(home)
  end
end
