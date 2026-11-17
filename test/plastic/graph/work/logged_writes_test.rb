# frozen_string_literal: true

require "digest"
require_relative "../../../test_helper"

# Every intent write stores its owning rows and one pending row together, and one work_log line follows.
class WorkLoggedWritesTest < Plastic::TestCase
  fixtures :empty

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def work = graphs.work

  def lines(id = "1") = graphs.retrieval.work_log(id)

  def kinds(id = "1") = lines(id).map(&:kind)

  def intent(title = "Alpha") = work.write_intent(title:)

  def forget(id = "1") = graphs.databases.fetch(:work).transaction { |batch| batch.remove(:work_log, intent_id: id) }

  def test_a_new_intent_stores_its_rows_first_and_one_opened_line_second
    intent

    assert_equal [["opened", "s-1", "Opened: Alpha"]], lines.map { |line| line.values_at(:kind, :session_id, :text) }
  end

  def test_a_ruling_appends_one_line
    intent
    work.add_ruling(intent_id: "1", text: "Flowbite styles every delivery")

    assert_equal %w[opened ruled], kinds
    assert_includes lines.last.text, "D1"
  end

  def test_the_go_ahead_appends_one_line_and_a_second_call_none
    intent
    2.times { work.approve_intent("1") }

    assert_equal %w[opened approved], kinds
  end

  def test_a_verdict_appends_one_line_with_its_round
    intent
    work.add_verdict(intent_id: "1", verdict: "accept", findings: "checked")

    assert_equal %w[opened verdict], kinds
    assert_includes lines.last.text, "accept"
  end

  def test_abandoning_appends_an_abandoned_line
    intent
    work.note_intent(work_intent, "note", "why it ends")
    work.abandon_intent("1")

    assert_equal %w[opened noted abandoned], kinds
  end

  def test_a_note_appends_a_line_with_the_path_and_the_full_hash_of_the_document
    intent
    work.note_intent(work_intent, "note", "one line")
    line = lines.last

    assert_equal ["noted", "outcome.md", Digest::SHA256.hexdigest(graphs.retrieval.fetch("1", "outcome.md").body)], line.values_at(:kind, :path, :sha256)
  end

  def work_intent = graphs.retrieval.intent("1")

  def test_a_revision_appends_a_wrote_line_with_the_hash_of_the_new_revision
    intent
    work.revise_intent(work.revision(work_intent, "Beta", nil))
    line = lines.last

    assert_equal "wrote", line.kind
    assert_match(/\A\h{64}\z/, line.sha256)
  end

  def claimed
    intent
    work.add_node(intent_id: "1", title: "Build")
    work.claim_node(intent_id: "1", id: "n1", by: "s-1")
  end

  def test_a_claim_and_a_done_move_append_a_line_each_with_the_node
    claimed
    work.done_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal [%w[claimed n1], %w[done n1]], lines.drop(2).map { |line| line.values_at(:kind, :node) }
  end

  def test_renewing_a_claim_appends_no_line
    claimed
    before = lines.size
    work.renew_claims("s-1")

    assert_equal before, lines.size
  end

  def test_a_node_move_that_wrote_nothing_appends_no_line
    claimed
    work.done_node(intent_id: "1", id: "n1", by: "s-other")

    assert_equal %w[opened added claimed], kinds
  end

  def test_positions_count_up_from_one
    intent
    work.add_ruling(intent_id: "1", text: "a")

    assert_equal [1, 2], lines.map(&:position)
  end

  def test_an_intent_converted_from_savepoints_is_not_given_an_opened_line
    intent
    forget
    graphs.databases.fetch(:work).transaction { |batch| batch.put(:work_log, { intent_id: "1", position: 1, at: Plastic.now, kind: "noted", text: "old line" }) }
    work.add_ruling(intent_id: "1", text: "x")

    assert_equal %w[noted ruled], kinds
  end

  def test_the_go_ahead_line_belongs_to_the_session_that_gave_it
    intent
    graphs("s-2").work.approve_intent("1")

    assert_equal "s-2", lines.last.session_id
  end

  def test_a_legacy_intent_gets_no_line_until_a_real_write
    intent
    forget
    graphs.databases.fetch(:work).transaction { |batch| batch.put(:work_log, { intent_id: "1", position: 1, at: Plastic.now, kind: "noted", text: "old line" }) }

    assert_equal [0, %w[noted]], [work.drain_log("1"), kinds]
  end
end
