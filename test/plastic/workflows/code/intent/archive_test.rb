# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/archive"

class ArchiveIntentTest < Plastic::TestCase
  def archive(intent_id = "1") = run_workflow(Plastic::Workflows::Code::Intent::Archive, intent_id:, older_than: nil)

  def test_a_done_intent_is_archived_and_its_rows_stay
    open_intent(status: "done")

    outcome, context = archive

    assert_equal [:done, ["intent: 1 archived"]], [outcome, context.printed]
    assert archived?("1")
    refute_nil retrieval.intent("1")
  end

  def test_an_open_intent_is_not_archived
    open_intent

    stop_workflow(Plastic::Workflows::Code::Intent::Archive, Plastic::Refused, intent_id: "1", older_than: nil)

    refute archived?("1")
  end

  def before_date(older_than = "2026-02-01") = run_workflow(Plastic::Workflows::Code::Intent::Archive, intent_id: nil, older_than:)

  def dated(title, status:, opened: "2026-01-01T00:00:00Z", closed: nil)
    intent = open_intent(title:, status: "future")
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = :status, opened_at = :opened, closed_at = :closed WHERE intent_id = :id",
        id: intent.intent_id, status:, opened:, closed:)
    end
    intent
  end

  def test_a_done_intent_closed_before_the_date_is_archived_with_one_line
    intent = dated("Old", status: "done", closed: "2026-01-10T00:00:00Z")

    outcome, context = before_date

    assert_equal [:done, ["intent: #{intent.intent_id} archived"], true], [outcome, context.printed, archived?(intent.intent_id)]
  end

  def test_a_done_intent_closed_at_the_date_or_after_it_is_passed_over_with_no_line
    intent = dated("Recent", status: "done", closed: "2026-03-01T00:00:00Z")

    _outcome, context = before_date

    assert_equal [false, ["intent: nothing to archive"]], [archived?(intent.intent_id), context.printed]
  end

  def test_a_future_intent_opened_before_the_date_is_archived
    intent = dated("Idea", status: "future", opened: "2026-01-05T00:00:00Z")

    before_date

    assert archived?(intent.intent_id)
  end

  def test_a_future_intent_opened_after_the_date_is_passed_over
    intent = dated("New idea", status: "future", opened: "2026-04-05T00:00:00Z")

    before_date

    refute archived?(intent.intent_id)
  end

  def test_a_closed_intent_with_no_close_date_is_skipped_and_named
    intent = dated("Undated", status: "done")

    _outcome, context = before_date

    assert_equal [false, ["intent: #{intent.intent_id} skipped, it is done with no close date"]], [archived?(intent.intent_id), context.printed]
  end

  def test_a_closed_intent_whose_close_date_holds_a_day_and_no_time_is_read_as_local_midnight_of_that_day
    intent = dated("Bare day", status: "done", closed: "2026-01-31")

    before_date

    assert archived?(intent.intent_id)
  end

  def test_a_closed_intent_whose_close_date_is_not_a_time_is_not_archived
    intent = dated("Garbled", status: "done", closed: "last week")

    before_date

    refute archived?(intent.intent_id)
  end

  def test_an_open_intent_opened_before_the_date_is_skipped_and_named
    intent = dated("Still going", status: "open")

    _outcome, context = before_date

    assert_equal [false, ["intent: #{intent.intent_id} skipped, it is open; end it first"]], [archived?(intent.intent_id), context.printed]
  end

  def test_an_open_intent_opened_after_the_date_is_passed_over_with_no_line
    dated("Fresh", status: "open", opened: "2026-05-01T00:00:00Z")

    _outcome, context = before_date

    assert_equal ["intent: nothing to archive"], context.printed
  end

  def test_an_intent_archived_before_is_passed_over_with_no_line
    intent = dated("Twice", status: "done", closed: "2026-01-10T00:00:00Z")
    before_date

    _outcome, context = before_date

    assert_equal [true, ["intent: nothing to archive"]], [archived?(intent.intent_id), context.printed]
  end

  def test_an_intent_that_a_live_intent_links_to_is_skipped_with_the_refusal
    target = dated("Target", status: "done", closed: "2026-01-10T00:00:00Z")
    linker = dated("Linker", status: "open", opened: "2026-05-01T00:00:00Z")
    store_graphs.work.add_link(from_ref: linker.intent_id, to_ref: target.intent_id, kind: "cites")

    _outcome, context = before_date

    assert_equal [false, ["intent: #{target.intent_id} skipped, intent #{linker.intent_id} links to #{target.intent_id}"]],
      [archived?(target.intent_id), context.printed]
  end

  def test_an_unknown_intent_is_not_archived
    stop_workflow(Plastic::Workflows::Code::Intent::Archive, intent_id: "9", older_than: nil)

    refute archived?("9")
  end
end
