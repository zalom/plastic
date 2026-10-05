# frozen_string_literal: true

require "digest"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/backup_list"

class WorkflowBackupListTest < Plastic::TestCase
  def keep_backup(bytes)
    path = File.join(FileUtils.mkdir_p(File.join(@plastic_home, "backups")).first, "b1.tar.gz")
    File.binwrite(path, bytes)
    row = { name: "b1.tar.gz", files: 1, bytes: 5, sha256: Digest::SHA256.hexdigest("kept!"), at: STAMP }
    store_graphs.databases[:home].transaction { |batch| batch.put(:backups, row) }
    path
  end

  def list = run_workflow(Plastic::Workflows::BackupList)

  def test_no_backups_says_so
    assert_equal [:done, ["no backups"]], list.then { |outcome, context| [outcome, context.printed] }
  end

  def test_an_unchanged_backup_is_listed_clean
    keep_backup("kept!")

    outcome, context = list

    assert_equal [:done, ["backup: b1.tar.gz, 5 bytes, #{STAMP}"]], [outcome, context.printed]
  end

  def test_a_changed_backup_is_flagged_and_fails_the_call
    keep_backup("other")

    outcome, context = list

    assert_equal ["backup: b1.tar.gz, 5 bytes, #{STAMP} (changed)"], context.printed
    assert_equal "code_backup_list, gate: a backup is missing or changed; see above", outcome.message
  end

  def test_a_missing_backup_is_flagged
    File.delete(keep_backup("kept!"))

    assert_equal ["backup: b1.tar.gz, 5 bytes, #{STAMP} (missing)"], list.last.printed
  end
end
