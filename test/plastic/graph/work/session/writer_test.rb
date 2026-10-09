# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkSessionWriterTest < Plastic::TestCase
  def work = Plastic::Graph.create(home: @plastic_home, store: "plastic").work

  def reader = Plastic::Graph.create(home: @plastic_home, store: "plastic").retrieval

  def test_open_session_sets_started_at_once_and_keeps_it_on_a_second_open
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    first = reader.session("s-1")
    work.open_session("s-1", harness: "codex", directory: "/a")
    second = reader.session("s-1")

    assert_equal [first.started_at, "codex"], [second.started_at, second.harness]
  end

  def test_stamp_turn_sets_the_last_turn_at_and_keeps_started_at
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    opened = reader.session("s-1")
    work.stamp_turn("s-1", harness: "claude-code", directory: "/a")
    stamped = reader.session("s-1")

    assert_equal opened.started_at, stamped.started_at
    refute_nil stamped.last_turn_at
  end

  def test_end_session_touches_only_ended_at_and_the_reason
    work.open_session("s-1", harness: "claude-code", directory: "/a")
    work.end_session("s-1", reason: "clear")
    session = reader.session("s-1")

    assert_equal ["s-1", "claude-code", "/a", "clear"], [session.session_id, session.harness, session.directory, session.end_reason]
    assert_predicate session, :ended?
  end

  def test_a_note_on_a_session_with_no_row_writes_the_row
    work.write_note("s-9", "picked up the review")

    assert_equal "picked up the review", reader.session("s-9").note
  end

  def test_take_lock_writes_the_lock_of_this_store_taken_and_renewed_together
    work.take_lock("1", session_id: "s-1", mode: "auto")
    lock = reader.lock("1")

    assert_equal ["plastic", "s-1", "auto", lock.taken_at], [lock.store, lock.session_id, lock.mode, lock.renewed_at]
  end

  def test_renew_locks_counts_every_lock_the_session_names_in_any_store
    work.take_lock("1", session_id: "s-1", mode: "auto")
    Plastic::Graph.create(home: @plastic_home, store: "other").work.take_lock("2", session_id: "s-1", mode: "auto")
    work.take_lock("3", session_id: "s-2", mode: "auto")

    assert_equal 2, work.renew_locks("s-1")
  end

  def test_renew_locks_of_a_session_with_no_lock_counts_none
    assert_equal 0, work.renew_locks("nobody")
  end
end
