# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/recap"
require_relative "../../../lib/plastic/hooks/compact_recap"

class CompactRecapTest < Plastic::TestCase
  fixtures :empty

  FIXTURES = File.expand_path("../../fixtures/hooks", __dir__)

  def event(name) = JSON.parse(File.read(File.join(FIXTURES, name)), symbolize_names: true)

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def recap(source, session: "s-1", directory: @home)
    Plastic::Hooks::Recap.new(graphs(session).retrieval, session_id: session, source:, directory:).lines(now: Time.now)
  end

  def claimed_intent
    work = graphs.work
    intent = work.write_intent(title: "Alpha")
    work.add_node(intent_id: intent.intent_id, title: "Build")
    work.add_node(intent_id: intent.intent_id, title: "Test")
    work.claim_node(intent_id: intent.intent_id, id: "n1", by: "s-1")
    intent
  end

  def test_the_compact_fixture_of_each_harness_gives_source_compact
    assert_equal %w[compact compact], %w[claude_code_session_start_compact.documented.json codex_session_start_compact.documented.json].map { |name| event(name)[:source] }
  end

  def test_a_compacted_session_prints_its_intent_its_claims_the_ready_nodes_the_last_lines_and_one_next_command
    intent = claimed_intent
    lines = recap("compact")

    assert_equal ["Plastic: the session was compacted. The rows below carry the state; run plastic graph resume.",
      "intent: #{intent.intent_id} Alpha", "claim: n1 Build", "ready: n2 Test"], lines.first(4)
    assert lines[4].start_with?("- ")
    assert_equal "next: plastic graph resume", lines.last
  end

  def test_a_compact_print_holds_no_intent_listing
    claimed_intent

    refute recap("compact").any? { |line| line.start_with?("active:", "future:", "finished:") }
  end

  def test_only_the_last_five_log_lines_print
    intent = claimed_intent
    4.times { |index| graphs.work.add_ruling(intent_id: intent.intent_id, text: "ruling #{index}") }

    assert_equal 5, recap("compact").count { |line| line.start_with?("- ") }
  end

  def test_the_intent_comes_from_the_newest_log_row_of_the_session_when_it_holds_no_node
    work = graphs.work
    intent = work.write_intent(title: "Alpha")

    assert_includes recap("compact"), "intent: #{intent.intent_id} Alpha"
  end

  def test_a_ready_node_with_no_claim_names_the_claim_as_the_next_command
    intent = graphs.work.write_intent(title: "Alpha")
    graphs.work.add_node(intent_id: intent.intent_id, title: "Build")

    assert_equal "next: plastic node claim #{intent.intent_id} n1", recap("compact").last
  end

  def test_a_closed_intent_is_not_the_intent_of_the_session
    graphs.work.write_intent(title: "Alpha", status: "done")

    assert_equal [Plastic::Hooks::CompactRecap::NO_INTENT], recap("compact")
  end

  def test_a_claim_in_a_closed_intent_does_not_hold_the_session_to_it
    work = graphs.work
    intent = work.write_intent(title: "Alpha", status: "done")
    work.add_node(intent_id: intent.intent_id, title: "Build")
    work.claim_node(intent_id: intent.intent_id, id: "n1", by: "s-1")

    assert_equal [Plastic::Hooks::CompactRecap::NO_INTENT], recap("compact")
  end

  def test_a_session_with_no_intent_gets_one_line_that_names_plastic_next
    assert_equal ["Plastic: the session was compacted and holds no intent. Run plastic next."], recap("compact", session: "s-9")
  end

  def test_startup_resume_and_clear_keep_their_print
    claimed_intent

    assert(recap("clear").any? { |line| line.start_with?("active: ") })
  end

  def test_a_codex_fork_prints_the_resume_line
    assert_equal recap("resume").first, recap("fork").first
  end
end
