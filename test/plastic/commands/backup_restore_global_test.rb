# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_restore"

class BackupRestoreGlobalTest < Plastic::TestCase
  include BackupHomes

  FIRST = "20260101100000"

  def test_restoring_the_global_store_replaces_its_own_databases
    home = fresh_home
    seed_store(home, "global")
    backup_at(home, at(2026, 1, 1, 10, 0, 0), slug: "global")
    add_intent(home, "global")

    assert_equal 0, restore_call(home, "--store", "global", "--timestamp", FIRST).code
    assert_equal 1, intent_count(home, "global")
  end
end
