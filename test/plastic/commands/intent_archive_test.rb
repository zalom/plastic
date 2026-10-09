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
    row = { intent_id: intent.intent_id, id: "D1", text: "a ruling", supersedes: nil, at: STAMP }
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

  def test_archiving_an_unlinked_done_intent_keeps_its_document_and_ruling_bytes
    intent = open_intent("Target")
    add_ruling(intent)
    mark_done(intent)

    call(intent.intent_id)

    assert_equal intent.page(retrieval.origin_id), archived_document(intent).body
    assert_equal "a ruling", archived_ruling(intent).text
  end

  def test_an_open_intents_link_refuses_the_archive
    target = open_intent("Target")
    mark_done(target)
    linker = open_intent("Linker")
    plastic("intent", "link", linker.intent_id, "cites", target.intent_id, table: Plastic::CLI::TABLE)

    result = call(target.intent_id)

    assert_call result, code: 3, out: RUN_ROW, err: "plastic: refused, intent 2 links to 1\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n"
    assert folder.exist?("#{target.dir}/#{target.file}")
  end

  def test_an_open_intent_exits_1_naming_its_state_and_offers_intent_end
    intent = open_intent("Target")

    result = call(intent.intent_id)

    assert_equal 1, result.code
    assert_includes result.err, "open"
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_a_hand_edited_file_is_captured_before_archive
    intent = open_intent("Target")
    mark_done(intent)
    write("#{intent.dir}/#{intent.file}", "edited by hand\n")

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute folder.exist?("#{intent.dir}/#{intent.file}")
  end

  def test_an_archive_that_failed_fails_again_on_the_next_call
    intent = open_intent("Target")
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal 1, result.code
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

  def test_archiving_a_missing_intent_reports_a_failure
    result = call("99")

    assert_call result, code: 1, out: RUN_ROW, err: ["no intent 99"]
  end

  def test_revert_restores_the_exact_snapshot_taken_at_archive_time
    intent = open_intent("Unsynced", status: "future")
    path = "#{intent.dir}/#{intent.file}"
    write(path, "owner edit not in document rows")
    call(intent.intent_id)
    call(intent.intent_id, "--revert")

    assert_equal "owner edit not in document rows", folder.read(path)
  end

  def test_revert_of_an_intent_that_was_never_archived_fails_and_leaves_it_live
    intent = open_intent("Open")
    call(intent.intent_id)

    result = call(intent.intent_id, "--revert")

    assert_call result, code: 1, out: RUN_ROW, err: ["not archived"]
    refute retrieval.archived?(intent.intent_id)
  end

  private

  def archived_document(intent) = retrieval.documents(intent.intent_id).find { |candidate| candidate.path == intent.file }

  def archived_ruling(intent) = retrieval.rulings(intent.intent_id).find { |candidate| candidate.id == "D1" }
end
