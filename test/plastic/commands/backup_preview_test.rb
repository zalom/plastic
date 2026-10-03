# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"

class BackupPreviewTest < Plastic::TestCase
  def test_backup_dry_run_reports_the_planned_archive_without_creating_a_home
    home = File.join(Dir.mktmpdir, ".plastic")
    result = plastic("backup", "--dry-run", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_includes result.out, "preview"
    refute_path_exists home
  end
end
