# frozen_string_literal: true

require_relative "../../test_helper"

class SessionsTest < Plastic::TestCase
  def graphs(session: nil) = Plastic::Graph.open(home: @plastic_home, store: "plastic", session:)

  def closed_run(subject, at: nil)
    run = Plastic::RoutineRun.fresh("intent end", subject).close(Plastic::Finished.new(next_command: nil, because: "done"), {})
    at ? run.with(updated_at: at) : run
  end

  def test_open_session_sets_started_at_once_and_keeps_it_on_a_second_open
    work = graphs.work
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    first = retrieval_home.session("s-1")
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    second = retrieval_home.session("s-1")

    assert_equal first.started_at, second.started_at
  end

  def test_stamp_turn_sets_the_last_turn_at_and_keeps_started_at
    work = graphs.work
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    opened = retrieval_home.session("s-1")
    work.stamp_turn("s-1", harness: "claude-code", directory: "/a")
    stamped = retrieval_home.session("s-1")

    assert_equal opened.started_at, stamped.started_at
    refute_nil stamped.last_turn_at
  end

  def test_end_session_touches_only_ended_at_and_the_reason
    work = graphs.work
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    work.end_session("s-1", reason: "clear")
    session = retrieval_home.session("s-1")

    assert_equal ["s-1", "claude-code", "/a", "clear"], [session.session_id, session.harness, session.directory, session.end_reason]
    assert_predicate session, :ended?
  end

  def test_a_session_with_no_row_reads_as_nil
    assert_nil retrieval_home.session("missing")
  end

  def test_previous_session_is_the_latest_other_session_by_turn_or_start
    work = graphs.work
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    work.open_session("s-2", harness: "claude-code", directory: "/a")

    assert_equal "s-1", retrieval_home.previous_session("s-2").session_id
  end

  def test_touched_names_the_intents_a_session_wrote_to_most_recent_first
    opened = graphs(session: "s-1")
    intent = opened.work.write_intent(title: "Alpha")
    opened.work.print_intent(intent.intent_id)

    assert_equal [intent.intent_id], opened.retrieval.touched("s-1")
  end

  def test_touched_finds_nothing_for_a_session_with_no_rows
    assert_empty retrieval_home.touched("nobody")
  end

  def test_touched_counts_a_run_whose_subject_is_a_title_through_its_facts_intent_id
    run = Plastic::RoutineRun.fresh("intent new", "Alpha")
      .close(Plastic::Finished.new(next_command: "plastic continue", because: "done"), { intent_id: "1" })
    graphs(session: "s-1").work.save_routine_run(run)

    assert_equal ["1"], retrieval_home.touched("s-1")
  end

  def test_touched_orders_the_most_recent_intent_first
    opened = graphs(session: "s-1")
    opened.work.save_routine_run(closed_run("1"))
    opened.work.save_routine_run(closed_run("2", at: (Time.now + 1).iso8601))

    assert_equal %w[2 1], opened.retrieval.touched("s-1")
  end

  def test_last_run_reads_the_latest_routine_run_naming_the_intent
    graphs.work.save_routine_run(Plastic::RoutineRun.fresh("intent end", "1"))

    assert_equal "1", retrieval_home.last_run("1").subject
  end

  def test_last_run_finds_nothing_for_an_untouched_intent
    assert_nil retrieval_home.last_run("9")
  end

  def test_last_run_stays_in_its_own_store
    Plastic::Graph.open(home: @plastic_home, store: "other").work.save_routine_run(Plastic::RoutineRun.fresh("intent end", "1"))

    assert_nil retrieval_home.last_run("1")
  end

  def test_a_second_session_rerunning_a_tool_moves_the_run_but_keeps_the_earlier_savepoint_lines
    intent_id = write_and_print_intent("s-1")
    second = graphs(session: "s-2")
    second.work.save_routine_run(Plastic::RoutineRun.fresh("intent end", intent_id))

    assert_equal "s-2", run_session_id(second, intent_id)
    assert_equal "s-1", second.retrieval.savepoints(intent_id).first.session_id
  end

  def write_and_print_intent(session)
    opened = graphs(session:)
    intent = opened.work.write_intent(title: "Alpha")
    opened.work.print_intent(intent.intent_id)
    intent.intent_id
  end

  def run_session_id(opened, subject)
    opened.databases[:home].row("SELECT session_id FROM routine_runs WHERE subject = :s", s: subject).fetch("session_id")
  end

  private

  def retrieval_home = Plastic::Graph.open(home: @plastic_home, store: "plastic").retrieval
end
