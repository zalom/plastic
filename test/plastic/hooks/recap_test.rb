# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/recap"

class RecapTest < Plastic::TestCase
  fixtures :empty

  def opened(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def recap(source: nil, session: "s-1")
    Plastic::Hooks::Recap.new(opened(session).retrieval, session_id: session, source:, directory: @home).lines
  end

  def printed_intent(title = "Alpha")
    work = opened.work
    work.write_intent(title:).intent_id.tap { |intent_id| work.print_intent(intent_id) }
  end

  def test_a_new_session_names_its_store_and_the_next_command
    assert_equal ["Plastic: a new session in store global. Run plastic next before anything else."], recap
  end

  def test_a_new_session_prints_the_previous_session_and_what_it_touched
    opened.work.open_session("s-1", harness: "claude-code", directory: @home)
    intent_id = printed_intent
    opened.work.end_session("s-1", reason: "clear")

    lines = recap(session: "s-2")

    assert lines.any? { |line| line.match?(/\Aprevious session s-1 ended .* \(clear\)\z/) }
    assert_includes lines, "touched: #{intent_id}"
  end

  def test_a_previous_session_still_running_prints_its_last_turn_and_nothing_touched
    opened.work.stamp_turn("s-1", directory: @home)

    lines = recap(session: "s-2")

    assert lines.any? { |line| line.match?(/\Aprevious session s-1 last turn \S+\z/) }
    refute lines.any? { |line| line.start_with?("touched:") }
  end

  def test_clear_prints_the_cleared_line_and_the_open_intents
    intent_id = printed_intent

    lines = recap(source: "clear")

    assert_equal "Plastic: the context was cleared. The rows below carry the state; run plastic graph resume.", lines.first
    assert_includes lines, "active: #{intent_id} Alpha (open)"
  end

  def test_clear_prints_the_intent_in_progress
    intent_id = printed_intent

    assert_includes recap(source: "clear"), "in progress: #{intent_id} Alpha"
  end

  def test_compact_prints_the_savepoint_lines_and_the_note
    printed_intent
    opened.work.write_note("s-1", "note text")

    lines = recap(source: "compact")

    assert_equal "Plastic: the session was compacted. The rows below carry the state; run plastic graph resume.", lines.first
    assert lines.any? { |line| line.include?("Opened: Alpha") }
    assert_equal "note: note text", lines.last
  end

  def test_the_intents_are_listed_by_group_with_their_state
    work = opened.work
    { "Alpha" => "done", "Side" => "parked", "Later" => "future", "Beta" => "open", "Moving" => "in_progress" }.each { |title, status| work.write_intent(title:, status:) }

    assert_equal ["active: 2 Side (parked)", "active: 4 Beta (open)", "active: 5 Moving (in_progress)", "future: 3 Later (future)", "finished: 1 Alpha (done)"],
      recap.grep(/\A(active|future|finished): /)
  end

  def test_the_groups_come_in_the_order_active_future_finished
    work = opened.work
    { "Alpha" => "done", "Later" => "future", "Beta" => "open" }.each { |title, status| work.write_intent(title:, status:) }

    assert_equal %w[active future finished], recap.grep(/\A(active|future|finished): /).map { |line| line[/\A\w+/] }
  end

  def test_an_open_intent_with_a_run_prints_the_last_run_and_its_next
    intent_id = opened.work.write_intent(title: "Beta").intent_id
    run = Plastic::RoutineRun.fresh("intent show", intent_id).with(status: "finished", next_command: "plastic next")
    opened.work.save_routine_run(run)

    assert_includes recap, "active: #{intent_id} Beta (open), last run intent show finished #{run.updated_at}, next: plastic next"
  end

  def test_a_group_over_the_cap_prints_ten_and_a_count_of_the_rest
    12.times { |n| opened.work.write_intent(title: "I#{n}") }

    lines = recap

    assert_equal 10, lines.grep(/\Aactive: \d/).size
    assert_includes lines, "active: and 2 more"
  end

  def test_a_resumed_session_says_so
    assert_equal ["Plastic: a resumed session. The rows below carry the state; run plastic graph resume."], recap(source: "resume")
  end
end
