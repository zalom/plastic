# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_revise"

class IntentReviseTest < Plastic::TestCase
  FILE = "1--alpha.md"

  def call(*args) = plastic("intent", "revise", *args, table: Plastic::CLI::TABLE)

  def body = retrieval.fetch("1", FILE).body

  def revisions
    store_graphs.databases.fetch(:knowledge).row("SELECT COUNT(*) AS n FROM document_revisions WHERE path = :path", path: FILE).fetch("n")
  end

  def set_status(status)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = '1'", status:)
    end
  end

  def test_a_revise_changes_the_title_row_and_the_head_revision
    open_intent

    result = call("1", "Beta, after grilling", "--why", "The owner moved the goal")

    assert_equal 0, result.code, result.err
    assert_equal "Beta, after grilling", retrieval.intent("1").title
    assert_includes body, "## Intent\n\nBeta, after grilling\n"
    assert_includes body, "## Context\n\nThe owner moved the goal\n"
    assert_equal 2, revisions
    assert_includes result.out, "next: plastic sync down"
  end

  def test_the_old_revision_still_reads_back_by_its_printed_reference
    open_intent

    result = call("1", "Beta, after grilling")
    reference = result.out[%r{history: (plastic://\S+)}, 1]

    assert_includes retrieval.fetch_reference(reference).fetch(:body), "## Intent\n\nAlpha\n"
  end

  def test_a_dry_run_prints_both_whats_and_writes_no_row
    open_intent

    result = call("1", "Beta, after grilling", "--dry-run")

    assert_equal 0, result.code, result.err
    assert_includes result.out, "what was: Alpha"
    assert_includes result.out, "what: Beta, after grilling"
    assert_equal "Alpha", retrieval.intent("1").title
    assert_equal 1, revisions
  end

  def test_a_done_intent_refuses_with_exit_3_and_no_row_written
    open_intent
    set_status("done")

    result = call("1", "Beta, after grilling")

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 is done"
    assert_equal "Alpha", retrieval.intent("1").title
    assert_equal 1, revisions
  end

  def test_a_parked_intent_is_revised
    open_intent
    set_status("parked")

    assert_equal 0, call("1", "Beta, after grilling").code
    assert_equal "Beta, after grilling", retrieval.intent("1").title
  end

  def test_an_unknown_intent_fails_with_exit_1
    result = call("9", "Beta, after grilling")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_an_empty_line_fails_with_exit_1_and_no_row_written
    open_intent

    result = call("1", "  ")

    assert_equal 1, result.code
    assert_includes result.err, "the new What is empty"
    assert_equal 1, revisions
  end

  def test_a_line_with_a_line_break_fails_with_exit_1
    open_intent

    result = call("1", "Beta\nGamma")

    assert_equal 1, result.code
    assert_includes result.err, "the new What is one line"
    assert_equal "Alpha", retrieval.intent("1").title
  end

  def test_the_same_line_fails_with_nothing_to_change
    open_intent

    result = call("1", "Alpha")

    assert_equal 1, result.code
    assert_includes result.err, "nothing to change"
    assert_equal 1, revisions
  end

  def test_a_hand_edited_intent_file_fails_with_no_row_written
    open_intent
    write("store/1--alpha/#{FILE}", "# changed by hand\n")

    result = call("1", "Beta, after grilling")

    assert_equal 1, result.code
    assert_includes result.err, "changed by hand"
    assert_equal 1, revisions
  end

  def test_an_intent_with_no_file_row_fails_with_exit_1
    open_intent
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.remove(:documents, intent_id: "1", path: FILE) }

    result = call("1", "Beta, after grilling")

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 has no file row"
  end

  def test_after_a_revise_sync_down_prints_the_file_with_no_conflict
    open_intent
    call("1", "Beta, after grilling")

    plan = store_graphs.work.sync_plan(:down, {})

    assert_empty plan.conflicts
    assert_includes plan.taking(:print).map(&:path), "store/1--alpha/#{FILE}"
  end
end
