# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"

# Covers backup preview and staging-failure boundaries.
class BackupPreviewTest < Plastic::TestCase
  # Fails before producing a staged path.
  class StageFailureWriter
    def stage = raise "injected staging failure"

    def discard(*) = flunk "a writer that did not stage an archive cannot discard one"
  end

  def test_backup_dry_run_reports_the_planned_archive_without_creating_a_home
    home = File.join(Dir.mktmpdir, ".plastic")
    result = plastic("backup", "--dry-run", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_includes result.out, "preview"
    refute_path_exists home
  end

  def test_backup_publisher_does_not_discard_when_staging_fails
    writer = StageFailureWriter.new
    publisher = Plastic::Graph::BackupPublisher.new(nil, nil, writer:)

    assert_raises(RuntimeError) { publisher.call }
  end

  def test_backup_staging_failure_before_a_path_is_safe
    home = Dir.mktmpdir
    File.binwrite(File.join(home, "backups"), "blocked")

    assert_raises(Errno::EEXIST) { Plastic::Graph::BackupWriter.new(home).stage }
  end
end
