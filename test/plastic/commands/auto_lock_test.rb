# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto_lock"

# Shared by the two lock command tests: a lock row of another session, live or lapsed.
module LockRows
  def lock(*argv, env: {}) = plastic("auto", "lock", *argv, env:, table: Plastic::CLI::TABLE)

  def hold(session_id, renewed_at: nil)
    return store_graphs.work.take_lock("1", session_id:, mode: "auto") unless renewed_at

    store_graphs.databases.fetch(:home).transaction do |batch|
      batch.put(:locks, { store: "global", intent_id: "1", session_id:, mode: "auto", taken_at: renewed_at, renewed_at: },
        statement: :insert)
    end
  end

  def lock_rows = store_graphs.databases.fetch(:home).rows("SELECT session_id FROM locks")
end

class AutoLockTest < Plastic::TestCase
  include LockRows

  def test_an_intent_with_no_lock_prints_no_lock_and_writes_nothing
    open_intent
    result = lock("1")

    assert_equal [0, "", true], [result.code, result.err, result.out.include?("no lock")]
    assert_empty lock_rows
  end

  def test_a_live_lock_prints_its_holder_its_start_and_that_it_is_live
    open_intent
    hold("s-9")
    result = lock("1")

    assert_equal 0, result.code
    assert_match(/s-9/, result.out)
    assert_match(/live/, result.out)
  end

  def test_a_lapsed_lock_prints_its_holder_and_that_it_lapsed_with_the_time
    open_intent
    hold("s-9", renewed_at: "2020-01-01T00:00:00Z")
    result = lock("1")

    assert_equal 0, result.code
    assert_match(/s-9/, result.out)
    assert_match(/lapsed.*2020-01-01/, result.out)
  end

  def test_a_missing_intent_fails
    result = lock("9")

    assert_equal 1, result.code
    assert_match(/9/, result.err)
  end
end
