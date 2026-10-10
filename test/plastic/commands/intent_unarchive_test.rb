# frozen_string_literal: true

require "digest"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"
require_relative "../../../scripts/lib/plastic/commands/intent_unarchive"

class IntentUnarchiveTest < Plastic::TestCase
  def archive_call(*args) = plastic("intent", "archive", *args, table: Plastic::CLI::TABLE)

  def restore_call(*args) = plastic("intent", "unarchive", *args, table: Plastic::CLI::TABLE)

  def mark_done(intent)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :id", id: intent.intent_id)
    end
  end

  def digest_of(intent) = Digest::SHA256.file(folder.path("#{intent.dir}/#{intent.file}")).hexdigest

  def test_every_file_matches_its_sha256_from_before_the_archive
    intent = open_intent("Target")
    before = digest_of(intent)
    mark_done(intent)
    archive_call(intent.intent_id)

    result = restore_call(intent.intent_id)

    assert_equal 0, result.code
    assert_equal before, digest_of(intent)
  end

  def test_restoring_an_intent_that_was_never_archived_exits_1
    intent = open_intent("Target")

    result = restore_call(intent.intent_id)

    assert_equal 1, result.code
  end

  def test_a_failed_restore_succeeds_once_the_intent_is_archived
    intent = open_intent("Target")
    mark_done(intent)
    restore_call(intent.intent_id)
    archive_call(intent.intent_id)

    result = restore_call(intent.intent_id)

    assert_equal 0, result.code
    assert folder.exist?("#{intent.dir}/#{intent.file}")
  end

  def archived_intent
    open_intent("Target").tap do |intent|
      mark_done(intent)
      archive_call(intent.intent_id)
    end
  end

  def test_restore_preserves_a_conflicting_file_and_the_archive_state
    intent = archived_intent
    path = "#{intent.dir}/#{intent.file}"
    write(path, "Unsynced owner edit")

    result = restore_call(intent.intent_id)

    assert_equal 1, result.code
    assert_equal "Unsynced owner edit", folder.read(path)
    assert store_graphs.retrieval.archived?(intent.intent_id)
  end

  def test_restore_refuses_a_partial_existing_tree_without_changing_it
    intent = archived_intent
    replace_identical_file(intent)

    result = restore_call(intent.intent_id)

    assert_equal 1, result.code
    assert store_graphs.retrieval.archived?(intent.intent_id)
  end

  def replace_identical_file(intent)
    document = store_graphs.retrieval.documents(intent.intent_id).find { |row| row.path == intent.file }
    write("#{intent.dir}/#{intent.file}", document.body)
  end

  def test_the_output_says_unarchived
    intent = archived_intent

    result = restore_call(intent.intent_id)

    assert_includes result.out, "intent: #{intent.intent_id} unarchived"
  end

  def test_archive_no_longer_takes_revert
    intent = archived_intent

    result = archive_call(intent.intent_id, "--revert")

    assert_equal 2, result.code
    assert_includes result.err, "--revert"
  end

  def test_the_snapshot_taken_at_archive_time_comes_back_exactly
    intent = open_intent("Unsynced", status: "future")
    path = "#{intent.dir}/#{intent.file}"
    write(path, "owner edit not in document rows")
    archive_call(intent.intent_id)
    restore_call(intent.intent_id)

    assert_equal "owner edit not in document rows", folder.read(path)
  end

  def test_an_intent_that_was_never_archived_fails_naming_it_and_stays_live
    intent = open_intent("Open")

    result = restore_call(intent.intent_id)

    assert_equal [1, true], [result.code, result.err.include?("not archived")]
    refute retrieval.archived?(intent.intent_id)
  end
end
