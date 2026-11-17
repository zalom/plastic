# frozen_string_literal: true

require_relative "../../../test_helper"

class BackupWorkflowTest < Plastic::TestCase
  include BackupHomes

  def test_a_backup_writes_a_folder_and_says_what_was_copied
    home = fresh_home
    result = backup_call(home, "--store", "alpha")

    assert_equal [0, 1], [result.code, folder_names(home).size], result.err
    assert_includes result.out, "backup"
  end
end
