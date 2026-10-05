# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_restore"

class BackupRestoreSyncTest < Plastic::TestCase
  include BackupHomes

  def sync(home, direction) = plastic("sync", direction, "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

  def bodies(home) = Plastic::Graph.open(home:, store: "alpha").retrieval.documents("1").map(&:body)

  def test_sync_up_after_restore_rereads_files_newer_than_the_backup
    home = fresh_home
    sync(home, "down")
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    File.write(File.join(home, "stores", "alpha", "store", "1--alpha", "1--alpha.md"), "\nWritten after the backup.\n", mode: "a")
    restore_call(home, "--store", "alpha", "--latest")
    sync(home, "up")

    assert(bodies(home).any? { |body| body.include?("Written after the backup.") })
  end
end
