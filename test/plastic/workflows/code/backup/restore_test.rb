# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/backup/restore"
require_relative "../../../../../lib/plastic/commands/backup"
require_relative "../../../../../lib/plastic/commands/backup/restore"

class RestoreBackupOutcomeTest < Plastic::TestCase
  def outcome = Plastic::Workflows::Code::Backup::Restore.outcomes.first

  def test_the_outcome_offers_no_sync_command
    assert_nil outcome.offers
  end

  def test_the_outcome_asks_the_person_whether_to_sync_up_or_down
    assert_includes outcome.because, "ask the person whether to run plastic sync down"
    assert_includes outcome.because, "plastic sync up"
  end
end

class RestoreBackupChoiceTest < Plastic::TestCase
  include BackupHomes

  def test_a_timestamp_with_no_backup_folder_refuses_and_names_it
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))

    assert_refused_with_usage restore_call(home, "--store", "alpha", "--timestamp", "20200101000000"), "no backup \"20200101000000\" of alpha"
  end

  def test_a_database_the_backup_lacks_refuses_as_a_usage_error
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), databases: %w[work_graph])

    assert_refused_with_usage restore_call(home, "--store", "alpha", "--timestamp", "20260101100000", "--databases", "references"), "references"
  end

  def test_latest_with_no_done_backup_refuses_and_names_the_store
    assert_refused_with_usage restore_call(fresh_home, "--store", "alpha", "--latest"), "no done backup of alpha to restore"
  end
end
