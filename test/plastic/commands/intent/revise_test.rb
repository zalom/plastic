# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/revise"
require "minitest/autorun"
require "tmpdir"

class IntentReviseTest < Plastic::TestCase
  FILE = "intent.md"

  def call(*args) = plastic("intent", "revise", *args, table: Plastic::CLI::TABLE)

  def body = retrieval.fetch("1", FILE).body

  def what_in_file = body[/^## Intent\n\n(.+)$/, 1]

  def set_status(status) = store_graphs.databases.fetch(:store).transaction { |batch| batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = '1'", status:) }

  def test_a_revise_changes_the_title_row_and_the_text_of_the_intent_file
    open_intent

    result = call("1", "Beta, after grilling")

    assert_equal 0, result.code, result.err
    assert_equal ["Beta, after grilling"] * 2, [retrieval.intent("1").title, what_in_file]
    refute_includes result.out, "plastic sync down"
  end

  def test_a_revise_with_why_writes_the_new_what_and_why_into_the_head_revision
    open_intent

    call("1", "Beta, after grilling", "--why", "The owner moved the goal")

    assert_includes body, "## Intent\n\nBeta, after grilling\n"
    assert_includes body, "## Context\n\nThe owner moved the goal\n"
  end

  def test_a_dry_run_prints_both_whats_and_writes_no_row
    open_intent

    result = call("1", "Beta, after grilling", "--dry-run")

    assert_call result, code: 0, out: ["what was: Alpha\nwhat: Beta, after grilling\n", "next: plastic intent revise 1 Beta,\\ after\\ grilling\n"]
    assert_equal ["Alpha"] * 2, [retrieval.intent("1").title, what_in_file]
  end

  def test_a_dry_run_prints_the_old_why_or_none
    open_intent

    first = call("1", "Beta", "--why", "The owner moved the goal")
    second = call("1", "Gamma", "--why", "The goal moved again", "--dry-run")

    assert_includes first.out, "why was: none\nwhy: The owner moved the goal\n"
    assert_call second, code: 0, out: ["why was: The owner moved the goal\nwhy: The goal moved again\n", "next: plastic intent revise 1 Gamma --why The\\ goal\\ moved\\ again\n"]
  end

  def test_a_done_intent_exits_1_with_no_row_written_and_offers_plastic_next
    open_intent
    set_status("done")

    result = call("1", "Beta, after grilling")

    assert_equal [1, true], [result.code, result.err.include?("intent 1 is done")]
    assert_match(/^next: plastic next/, result.out)
    assert_equal ["Alpha"] * 2, [retrieval.intent("1").title, what_in_file]
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

  def test_an_empty_line_is_a_usage_error_with_no_row_written
    open_intent

    result = call("1", "  ")

    assert_equal 2, result.code
    assert_includes result.err, "missing LINE"
    assert_equal "Alpha", what_in_file
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
    assert_equal "Alpha", what_in_file
  end

  def test_a_hand_edited_intent_file_fails_with_no_row_written
    open_intent
    write("store/1--alpha/#{FILE}", "# changed by hand\n")

    result = call("1", "Beta, after grilling")

    assert_equal 1, result.code
    assert_includes result.err, "changed since its last print on this home"
    assert_equal "Alpha", what_in_file
  end

  def test_an_intent_with_no_file_row_fails_with_exit_1
    open_intent
    store_graphs.databases.fetch(:store).transaction { |batch| batch.remove(:documents, intent_id: "1", path: FILE) }

    result = call("1", "Beta, after grilling")

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 has no file row"
  end

  def test_after_a_revise_the_file_already_equals_the_rows
    open_intent
    call("1", "Beta, after grilling")

    plan = store_graphs.work.sync_plan(:down, {})

    assert_empty plan.conflicts
    refute_includes plan.entries_for(:print).map(&:path), "store/1--alpha/#{FILE}"
  end
end

class IntentReviseCommandTest < Plastic::TestCase
  def test_the_command_revises_an_intent_through_the_plastic_helper
    plastic("intent", "new", "Alpha", table: Plastic::CLI::TABLE)

    call = plastic("intent", "revise", "1", "Beta, after grilling", "--why", "The owner moved the goal", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "what: Beta, after grilling"
    assert_equal [{ "title" => "Beta, after grilling" }], store_graphs.databases.fetch(:store).rows("SELECT title FROM intents").map { |row| row.to_h.transform_keys(&:to_s) }
  end
end

class IntentReviseImportedTest < Plastic::TestCase
  def call(*args) = plastic("intent", "revise", *args, table: Plastic::CLI::TABLE)

  def test_an_imported_folder_keeps_its_own_file_through_a_revise
    page = "---\nid: \"2\"\nintent: \"Beta\"\ncreated: \"#{STAMP}\"\n---\n\n# 2 - Beta\n"
    write("store/2--beta/2--beta.md", page)
    plastic("sync", "up", table: Plastic::CLI::TABLE)

    result = call("2", "Beta, revised")
    rows = store_graphs.databases.fetch(:store).rows("SELECT path FROM documents WHERE intent_id = :id AND path LIKE :like", id: "2", like: "%beta.md")

    assert_equal 0, result.code, result.err
    assert_equal ["2--beta.md"], rows.map { |row| row.fetch("path") }
  end
end
