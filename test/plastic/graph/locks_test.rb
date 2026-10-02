# frozen_string_literal: true

require_relative "../../test_helper"

class LocksTest < Plastic::TestCase
  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def test_take_lock_writes_a_row_taken_and_renewed_now
    store_graphs.work.take_lock("1", session_id: "s-1", mode: "auto")
    lock = retrieval.lock("1")

    assert_equal ["global", "1", "s-1", "auto"], [lock.store, lock.intent_id, lock.session_id, lock.mode]
    assert_equal lock.taken_at, lock.renewed_at
  end

  def test_a_lock_with_no_row_reads_as_nil
    assert_nil retrieval.lock("9")
  end

  def test_a_lock_renewed_moments_ago_is_live
    put(:home, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: Plastic.now, renewed_at: Plastic.now })

    assert_predicate retrieval.lock("1"), :live?
  end

  def test_a_lock_renewed_before_the_ttl_is_lapsed
    old = (Time.now - 3600).iso8601
    put(:home, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: old, renewed_at: old })

    refute_predicate retrieval.lock("1"), :live?
  end

  def test_renew_locks_updates_every_row_this_session_holds_and_counts_them
    store_graphs.work.take_lock("1", session_id: "s-1", mode: "auto")
    store_graphs.work.take_lock("2", session_id: "s-1", mode: "auto")

    assert_equal 2, store_graphs.work.renew_locks("s-1")
  end

  def test_renew_locks_finds_nothing_for_a_session_with_no_locks
    assert_equal 0, store_graphs.work.renew_locks("nobody")
  end

  def test_locks_of_lists_every_lock_a_session_holds_any_store
    store_graphs.work.take_lock("1", session_id: "s-1", mode: "auto")

    assert_equal ["1"], retrieval.locks_of("s-1").map(&:intent_id)
  end

  def test_ready_nodes_skips_a_node_waiting_on_an_undone_need
    put(:work, :nodes, { intent_id: "1", id: "a", state: "pending" })
    put(:work, :nodes, { intent_id: "1", id: "b", state: "pending" })
    put(:work, :edges, { intent_id: "1", from: "a", to: "b", kind: "needs" })

    assert_equal ["a"], retrieval.ready_nodes("1").map(&:id)
  end

  def test_ready_nodes_includes_a_node_whose_need_is_done
    put(:work, :nodes, { intent_id: "1", id: "a", state: "done" })
    put(:work, :nodes, { intent_id: "1", id: "b", state: "pending" })
    put(:work, :edges, { intent_id: "1", from: "a", to: "b", kind: "needs" })

    assert_equal ["b"], retrieval.ready_nodes("1").map(&:id)
  end
end
