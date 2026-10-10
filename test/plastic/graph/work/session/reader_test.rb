# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkSessionReaderTest < Plastic::TestCase
  def graphs(session: nil, store: "plastic") = Plastic::Graph.create(home: @plastic_home, store:, session:)

  def reader = graphs.retrieval

  def opened(session_id, directory: "/a")
    graphs.work.open_session(session_id, harness: "claude-code", directory:)
  end

  def closed_run(subject, at: nil)
    run = Plastic::RoutineRun.fresh("intent end", subject).close(Plastic::Finished.new(next_command: nil, because: "done"), {})
    at ? run.with(updated_at: at) : run
  end

  def test_a_session_with_no_row_reads_as_nil
    assert_nil reader.session("missing")
  end

  def test_previous_session_is_the_latest_other_session_of_the_store
    opened("s-1")
    opened("s-2")

    assert_equal "s-1", reader.previous_session("s-2").session_id
  end

  def test_a_predecessor_prefers_the_session_that_ended_for_the_reason_asked
    opened("s-1")
    graphs.work.end_session("s-1", reason: "clear")
    opened("s-2")
    opened("s-3")

    assert_equal "s-1", reader.predecessor("s-3", directory: "/a", prefer_reason: "clear").session_id
  end

  def test_a_predecessor_falls_back_to_any_directory_when_none_matches
    opened("s-1", directory: "/b")
    opened("s-2")

    assert_equal "s-1", reader.predecessor("s-2", directory: "/a").session_id
  end

  def test_a_lone_session_has_no_predecessor
    opened("s-1")

    assert_nil reader.predecessor("s-1")
  end

  def test_locks_of_lists_the_session_locks_in_every_store
    graphs.work.take_lock("1", session_id: "s-1", mode: "auto")
    graphs(store: "other").work.take_lock("2", session_id: "s-1", mode: "auto")

    assert_equal [%w[plastic 1], %w[other 2]].sort, reader.locks_of("s-1").map { |lock| [lock.store, lock.intent_id] }.sort
  end

  def test_the_lock_of_an_intent_in_another_store_is_not_this_store_lock
    graphs(store: "other").work.take_lock("1", session_id: "s-1", mode: "auto")

    assert_nil reader.lock("1")
  end

  def test_routine_run_reads_the_run_of_one_tool_on_one_subject
    graphs.work.save_routine_run(Plastic::RoutineRun.fresh("intent end", "1"))

    assert_equal ["intent end", "1"], reader.routine_run("intent end", "1").then { |run| [run.tool, run.subject] }
  end

  def test_touched_names_the_intents_a_session_wrote_to
    session = graphs(session: "s-1")
    intent = session.work.write_intent(title: "Alpha")
    session.work.print_intent(intent.intent_id)

    assert_equal [intent.intent_id], session.retrieval.touched("s-1")
  end

  def test_touched_finds_nothing_for_a_session_with_no_rows
    assert_empty reader.touched("nobody")
  end

  def test_touched_counts_a_run_whose_subject_is_a_title_through_its_facts_intent_id
    run = Plastic::RoutineRun.fresh("intent new", "Alpha")
      .close(Plastic::Finished.new(next_command: "plastic continue", because: "done"), { intent_id: "1" })
    graphs(session: "s-1").work.save_routine_run(run)

    assert_equal ["1"], reader.touched("s-1")
  end

  def test_touched_orders_the_most_recent_intent_first
    session = graphs(session: "s-1")
    session.work.save_routine_run(closed_run("1", at: STAMP))
    session.work.save_routine_run(closed_run("2", at: "2026-10-05T10:00:01+02:00"))

    assert_equal %w[2 1], session.retrieval.touched("s-1")
  end

  def test_last_run_reads_the_latest_routine_run_naming_the_intent
    graphs.work.save_routine_run(Plastic::RoutineRun.fresh("intent end", "1"))

    assert_equal "1", reader.last_run("1").subject
  end

  def test_last_run_finds_nothing_for_an_untouched_intent
    assert_nil reader.last_run("9")
  end

  def test_last_run_stays_in_its_own_store
    graphs(store: "other").work.save_routine_run(Plastic::RoutineRun.fresh("intent end", "1"))

    assert_nil reader.last_run("1")
  end
end
