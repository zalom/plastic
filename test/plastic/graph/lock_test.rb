# frozen_string_literal: true

require_relative "../../test_helper"

class LockTest < Plastic::TestCase
  def lock(renewed_at) = Plastic::Graph::Lock.new("global", "1", "s-1", "auto", renewed_at, renewed_at)

  def at(seconds) = Time.iso8601(STAMP) + seconds

  def test_a_lock_renewed_moments_ago_is_live
    assert lock(STAMP).live?(at(60))
  end

  def test_a_lock_renewed_exactly_one_ttl_ago_is_still_live
    assert lock(STAMP).live?(at(Plastic::Graph::Lock::TTL))
  end

  def test_a_lock_renewed_before_the_ttl_is_lapsed
    refute lock(STAMP).live?(at(Plastic::Graph::Lock::TTL + 1))
  end

  def test_a_lock_reads_from_its_home_row
    store_graphs.databases[:home].transaction do |batch|
      batch.put(:locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: STAMP, renewed_at: STAMP })
    end

    assert_equal lock(STAMP), retrieval.lock("1")
  end

  def test_a_lock_with_no_row_reads_as_nil
    assert_nil retrieval.lock("9")
  end
end
