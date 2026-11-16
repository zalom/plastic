# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaRunnerHomeTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def copies(home) = Dir.glob(File.join(home, "backups", "local-*.db"))

  def test_an_old_layout_home_leaves_one_checked_copy_of_local_db_at_version_zero
    home = old_layout(fresh_home)
    Runner.new(home:, now: NOW).call

    assert_equal [File.join(home, "backups", "local-20261116120000.db")], copies(home)
    assert_equal [0, "ok"], [read_value(copies(home).first, "PRAGMA user_version"), read_value(copies(home).first, "PRAGMA quick_check")]
  end

  def test_a_home_that_is_current_leaves_no_copy
    home = fresh_home
    Runner.new(home:, now: NOW).call

    assert_empty copies(home)
  end

  def test_a_home_whose_copy_cannot_be_made_stays_behind_and_is_reported
    home = old_layout(fresh_home)
    File.write(File.join(home, "backups"), "a file where the folder should be")
    report = Runner.new(home:, now: NOW).call

    assert_equal [0, ["home"]], [user_versions(home).fetch(File.join(home, "local.db")), report.failed]
  end
end
