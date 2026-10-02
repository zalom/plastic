# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"

class ArchiveSyncTest < Plastic::TestCase
  def archive(intent, *options)
    plastic("intent", "archive", intent.intent_id, *options, table: Plastic::CLI::TABLE)
  end

  def test_reverted_hand_edits_conflict_instead_of_being_overwritten_by_sync_down
    intent = open_intent("Unsynced", status: "future")
    path = "#{intent.dir}/#{intent.file}"
    write(path, "owner edit not in document rows")
    archive(intent)
    archive(intent, "--revert")

    result = plastic("sync", "down", table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
    assert_equal "owner edit not in document rows", folder.read(path)
  end

  def test_revert_after_failed_archive_does_not_resume_the_archive_operation
    intent = open_intent("Open")
    archive(intent)

    result = archive(intent, "--revert")

    assert_equal 1, result.code
    assert_includes result.err, "not archived"
    refute retrieval.archived?(intent.intent_id)
  end
end
