# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/recap"

class RecapLockTest < Plastic::TestCase
  fixtures :empty

  def opened(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def printed_intent(title = "Alpha")
    work = opened.work
    work.write_intent(title:).intent_id.tap { |intent_id| work.print_intent(intent_id) }
  end

  def lock_intent
    intent_id = printed_intent
    opened.work.take_lock(intent_id, session_id: "s-1", mode: "auto")
    [intent_id, opened.retrieval.lock(intent_id)]
  end

  def expired_lines(now)
    Plastic::Hooks::Recap.new(opened.retrieval, session_id: "s-1", source: "resume", directory: @home).lines(now:).grep(/the lock of this session expired/)
  end

  def test_an_own_lock_past_its_window_prints_the_expired_line_with_the_auto_command
    intent_id, lock = lock_intent
    later = Time.parse(lock.renewed_at) + Plastic::Graph::Lock::TTL + 1

    lines = Plastic::Hooks::Recap.new(opened.retrieval, session_id: "s-1", source: "resume", directory: @home).lines(now: later)

    assert_includes lines, "intent #{intent_id}: the lock of this session expired (last renewed #{lock.renewed_at}); plastic auto #{intent_id} locks it again"
  end

  def test_an_own_lock_within_its_window_prints_no_expired_line
    _intent_id, lock = lock_intent
    within = Time.parse(lock.renewed_at) + 1

    assert_empty expired_lines(within)
  end

  def test_a_lock_of_another_session_prints_no_expired_line
    intent_id = printed_intent
    opened.work.take_lock(intent_id, session_id: "s-2", mode: "auto")
    later = Time.parse(opened.retrieval.lock(intent_id).renewed_at) + Plastic::Graph::Lock::TTL + 1

    assert_empty expired_lines(later)
  end

  def expired_long_after(lock) = Time.parse(lock.renewed_at) + Plastic::Graph::Lock::TTL + 1

  def close_intent(intent_id, status)
    opened.databases.fetch(:work).transaction { |batch| batch.write(:intents, "UPDATE intents SET status = '#{status}' WHERE intent_id = :intent_id", intent_id:) }
  end

  def test_a_lock_on_a_done_intent_prints_no_expired_line
    intent_id, lock = lock_intent
    close_intent(intent_id, "done")

    assert_empty expired_lines(expired_long_after(lock))
  end

  def test_a_lock_on_an_abandoned_intent_prints_no_expired_line
    intent_id, lock = lock_intent
    close_intent(intent_id, "abandoned")

    assert_empty expired_lines(expired_long_after(lock))
  end

  def test_a_lock_on_an_intent_that_no_longer_exists_prints_no_expired_line
    intent_id, lock = lock_intent
    opened.databases.fetch(:work).transaction { |batch| batch.write(:intents, "DELETE FROM intents WHERE intent_id = :intent_id", intent_id:) }

    assert_empty expired_lines(expired_long_after(lock))
  end

  def test_a_lock_of_another_store_prints_no_expired_line
    stamp = "2026-01-01T00:00:00Z"
    opened.databases.fetch(:local).transaction do |batch|
      batch.put(:locks, { store: "other", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: stamp, renewed_at: stamp }, statement: :insert)
    end

    assert_empty expired_lines(Time.iso8601(stamp) + Plastic::Graph::Lock::TTL + 1)
  end
end
