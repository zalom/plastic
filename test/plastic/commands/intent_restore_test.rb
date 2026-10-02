# frozen_string_literal: true

require "digest"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"
require_relative "../../../scripts/lib/plastic/commands/intent_restore"

class IntentRestoreTest < Plastic::TestCase
  def archive_call(*args) = plastic("intent", "archive", *args, table: Plastic::CLI::TABLE)

  def restore_call(*args) = plastic("intent", "restore", *args, table: Plastic::CLI::TABLE)

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

  def test_restore_accepts_an_identical_existing_file
    intent = archived_intent
    replace_identical_file(intent)

    result = restore_call(intent.intent_id)

    assert_equal 0, result.code
    refute store_graphs.retrieval.archived?(intent.intent_id)
  end

  def replace_identical_file(intent)
    document = store_graphs.retrieval.documents(intent.intent_id).find { |row| row.path == intent.file }
    write("#{intent.dir}/#{intent.file}", document.body)
  end
end
