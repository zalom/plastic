# frozen_string_literal: true

require_relative "../../test_helper"

class LockTest < Plastic::TestCase
  Lock = Plastic::Graph::Lock
  Liveness = Plastic::Graph::Lock::Liveness
  Claim = Plastic::Graph::Lock::Claim

  def lock(renewed_at, store: "global") = Lock.new(store, "1", "s-1", "auto", renewed_at, renewed_at)

  def at(seconds) = Time.iso8601(STAMP) + seconds

  def lapsed = at(Lock::TTL + 1)

  def liveness(ended_at: nil, claims: []) = Liveness.new(lock(STAMP), ended_at, claims)

  def claim(seconds_after_stamp) = Claim.new("n1", at(seconds_after_stamp).iso8601)

  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def test_a_lock_renewed_moments_ago_is_live
    assert liveness.live?(at(60))
  end

  def test_a_lock_renewed_exactly_one_ttl_ago_is_still_live
    assert liveness.live?(at(Lock::TTL))
  end

  def test_a_lock_renewed_before_the_ttl_is_lapsed
    refute liveness.live?(lapsed)
  end

  def test_a_renewed_lock_says_it_was_renewed
    assert_equal "renewed within 30 minutes", liveness.why(at(60))
  end

  def test_a_lapsed_lock_with_a_claim_inside_the_node_limit_is_live
    held = liveness(claims: [claim(0)])

    assert held.live?(at(Lock::NODE_LIMIT))
    assert_equal "node n1 open since #{claim(0).claimed_at}", held.why(at(Lock::NODE_LIMIT))
  end

  def test_a_lapsed_lock_with_a_claim_past_the_node_limit_is_expired
    held = liveness(claims: [claim(0)])

    refute held.live?(at(Lock::NODE_LIMIT + 1))
    assert_equal "no renewal within 30 minutes and no open node", held.why(at(Lock::NODE_LIMIT + 1))
  end

  def test_a_lapsed_lock_with_no_claim_is_expired
    assert_equal "no renewal within 30 minutes and no open node", liveness.why(lapsed)
  end

  def test_a_lock_of_an_ended_session_is_not_live_however_fresh
    ended = liveness(ended_at: STAMP, claims: [claim(0)])

    refute ended.live?(at(60))
    assert_equal "session s-1 ended #{STAMP}", ended.why(at(60))
  end

  def test_liveness_reads_the_ended_session_from_its_row
    put(:local, :sessions, { session_id: "s-1", store: "global", ended_at: STAMP })

    assert_equal STAMP, retrieval.liveness(lock(STAMP)).ended_at
  end

  def test_liveness_reads_only_the_nodes_this_session_claimed_in_the_intent
    put(:work, :nodes, { intent_id: "1", id: "n1", state: "claimed", by: "s-1", updated_at: STAMP })
    put(:work, :nodes, { intent_id: "1", id: "n2", state: "claimed", by: "s-2", updated_at: STAMP })
    put(:work, :nodes, { intent_id: "1", id: "n3", state: "done", by: "s-1", updated_at: STAMP })
    put(:work, :nodes, { intent_id: "2", id: "n1", state: "claimed", by: "s-1", updated_at: STAMP })

    assert_equal [Claim.new("n1", STAMP)], retrieval.liveness(lock(STAMP)).claims
  end

  def test_a_lock_of_another_store_reads_no_claims
    put(:work, :nodes, { intent_id: "1", id: "n1", state: "claimed", by: "s-1", updated_at: STAMP })

    assert_empty retrieval.liveness(lock(STAMP, store: "other")).claims
  end

  def test_a_lock_reads_from_its_home_row
    put(:local, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: STAMP, renewed_at: STAMP })

    assert_equal lock(STAMP), retrieval.lock("1")
  end

  def test_a_lock_with_no_row_reads_as_nil
    assert_nil retrieval.lock("9")
  end
end
