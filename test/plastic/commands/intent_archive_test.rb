# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_link"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"

class IntentArchiveTest < Plastic::TestCase
  def call(*args) = plastic("intent", "archive", *args, table: Plastic::CLI::TABLE)

  def mark_done(intent)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :id", id: intent.intent_id)
    end
  end

  def add_ruling(intent)
    row = { intent_id: intent.intent_id, id: "D1", text: "a ruling", supersedes: nil, at: Plastic.now }
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.put(:rulings, row, statement: :insert) }
  end

  def test_archiving_an_unlinked_done_intent_clears_the_folder
    intent = open_intent("Target")
    add_ruling(intent)
    mark_done(intent)

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute folder.exist?("#{intent.dir}/#{intent.file}")
  end

  def test_archiving_an_unlinked_done_intent_keeps_the_intent_row
    intent = open_intent("Target")
    mark_done(intent)

    call(intent.intent_id)

    assert retrieval.intent(intent.intent_id)
  end

  def test_archiving_an_unlinked_done_intent_keeps_its_document_and_ruling
    intent = open_intent("Target")
    add_ruling(intent)
    mark_done(intent)

    call(intent.intent_id)

    assert_equal 1, retrieval.documents(intent.intent_id).size
    assert_equal 1, retrieval.rulings(intent.intent_id).size
  end

  def test_an_open_intents_link_refuses_the_archive
    target = open_intent("Target")
    mark_done(target)
    linker = open_intent("Linker")
    plastic("intent", "link", linker.intent_id, "cites", target.intent_id, table: Plastic::CLI::TABLE)

    result = call(target.intent_id)

    assert_equal 3, result.code
    assert folder.exist?("#{target.dir}/#{target.file}")
  end

  def test_an_open_intent_refuses_the_archive_naming_its_state
    intent = open_intent("Target")

    result = call(intent.intent_id)

    assert_equal 3, result.code
    assert_includes "#{result.out}#{result.err}", "open"
  end

  def test_a_hand_edited_file_is_captured_before_archive
    intent = open_intent("Target")
    mark_done(intent)
    write("#{intent.dir}/#{intent.file}", "edited by hand\n")

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute folder.exist?("#{intent.dir}/#{intent.file}")
  end

  def test_sync_down_after_an_archive_prints_nothing_back
    intent = open_intent("Target")
    mark_done(intent)
    call(intent.intent_id)

    result = plastic("sync", "down", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    refute folder.exist?(intent.dir)
  end

  def test_a_refused_archive_is_refused_again_on_the_next_call
    intent = open_intent("Target")
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal 3, result.code
    refute retrieval.archived?(intent.intent_id)
  end

  def test_an_intent_refused_while_open_archives_once_it_is_done
    intent = open_intent("Target")
    call(intent.intent_id)
    mark_done(intent)

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert retrieval.archived?(intent.intent_id)
  end

  def test_archiving_an_archived_intent_finishes_idempotently
    intent = open_intent("Target")
    mark_done(intent)
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert retrieval.archived?(intent.intent_id)
  end
end
