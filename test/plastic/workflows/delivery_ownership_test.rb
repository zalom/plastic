# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/delivery_ownership"

class WorkflowDeliveryOwnershipTest < Plastic::TestCase
  Context = Data.define(:retrieval, :intent_id, :session)

  def problem(session: "s-1") = Plastic::Workflows::DeliveryOwnership.problem(Context.new(retrieval, "1", session))

  def lock(session_id, renewed_at: Time.now.utc.iso8601)
    row = { store: retrieval.store, intent_id: "1", session_id:, mode: "auto", taken_at: renewed_at, renewed_at: }
    store_graphs.databases[:local].transaction { |batch| batch.put(:locks, row) }
  end

  def test_a_live_lock_of_another_session_is_the_problem
    lock("s-2")

    assert_equal "intent 1 is locked by session s-2", problem
  end

  def test_a_lock_of_this_session_is_no_problem
    lock("s-1")

    assert_nil problem
  end

  def test_an_expired_lock_of_another_session_is_no_problem
    lock("s-2", renewed_at: STAMP)

    assert_nil problem
  end

  def test_no_lock_is_no_problem
    assert_nil problem
  end
end
