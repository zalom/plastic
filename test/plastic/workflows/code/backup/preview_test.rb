# frozen_string_literal: true

require_relative "../../../../test_helper"

class BackupPreviewWorkflowTest < Plastic::TestCase
  include BackupHomes

  def test_a_dry_run_previews_the_folder_and_writes_nothing
    home = fresh_home
    result = backup_call(home, "--store", "alpha", "--dry-run")

    assert_equal [0, 0], [result.code, folder_names(home).size], result.err
    assert_includes result.out, "preview: backup alpha/"
    assert_includes result.out, "the original store was not changed"
  end
end
