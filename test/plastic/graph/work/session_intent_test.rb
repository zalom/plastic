# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkSessionIntentTest < Plastic::TestCase
  fixtures :empty

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def intent_of(session) = Plastic::Graph::Work::SessionIntent.new(graphs.retrieval, session).intent

  def test_a_held_node_in_an_open_intent_comes_before_a_newer_log_line
    work = graphs.work
    work.write_intent(title: "Alpha")
    work.add_node(intent_id: "1", title: "Build")
    work.claim_node(intent_id: "1", id: "n1", by: "s-1")
    work.write_intent(title: "Beta")

    assert_equal "1", intent_of("s-1").intent_id
  end

  def test_with_no_held_node_the_newest_line_of_the_session_names_the_intent
    work = graphs.work
    work.write_intent(title: "Alpha")
    work.write_intent(title: "Beta")
    work.add_ruling(intent_id: "1", text: "newest")

    assert_equal "1", intent_of("s-1").intent_id
  end

  def test_a_closed_intent_is_skipped
    graphs.work.write_intent(title: "Alpha", status: "done")

    assert_nil intent_of("s-1")
  end

  def test_a_session_that_wrote_nothing_has_no_intent
    graphs.work.write_intent(title: "Alpha")

    assert_nil intent_of("s-other")
  end

  def test_the_newest_line_of_an_open_intent_wins_over_a_newer_line_of_a_closed_one
    work = graphs.work
    work.write_intent(title: "Alpha")
    work.write_intent(title: "Beta", status: "done")

    assert_equal "1", intent_of("s-1").intent_id
  end
end
