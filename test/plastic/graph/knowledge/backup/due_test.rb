# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupDueTest < Plastic::TestCase
  include BackupHomes
  include BackupTriggers

  Due = Plastic::Graph::Knowledge::Backup::Due

  def due(home, now, slug: "alpha") = Due.new(home:, slug:, now:)

  def test_a_store_with_no_backup_takes_one_and_records_why
    home = fresh_home

    due(home, SEEDED).call("session start")

    assert_equal ["session start"], backup_reasons(home)
  end

  def test_a_store_whose_newest_backup_is_older_than_twelve_hours_takes_one
    home = stale_home
    add_intent(home)

    due(home, THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [nil, "sync up"], backup_reasons(home)
  end

  def test_a_store_whose_newest_backup_is_twelve_hours_old_or_less_takes_none
    home = stale_home
    add_intent(home)

    due(home, ELEVEN_HOURS_LATER).call("sync up")

    assert_equal [nil], backup_reasons(home)
  end

  def test_a_store_that_did_not_change_takes_none_however_old_its_newest_backup
    home = stale_home

    due(home, THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [nil], backup_reasons(home)
  end

  def test_a_damaged_database_takes_no_backup_and_raises_nothing
    home = stale_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph"), "not a database")

    result = due(home, THIRTEEN_HOURS_LATER).call("sync up")

    assert_equal [:failed, [nil]], [result.status, backup_reasons(home)]
  end

  def test_a_store_that_does_not_exist_takes_none
    home = fresh_home

    assert_equal :missing, due(home, SEEDED, slug: "nowhere").call("session start").status
  end
end
