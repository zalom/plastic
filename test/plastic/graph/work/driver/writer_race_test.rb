# frozen_string_literal: true

require_relative "../../../../test_helper"

# Two sessions that read the same lapsed driver claim cannot both take it: the write is guarded by the holder it read.
class WorkDriverWriterRaceTest < Plastic::TestCase
  START = Time.utc(2026, 11, 24, 8, 0, 0)

  # A clock whose first reading lets a rival session take the claim, after the holder was read and before the write.
  class RacingClock
    def initialize(now, &rival)
      @now = now
      @rival = rival
    end

    def now
      rival = @rival
      @rival = nil
      rival&.call
      @now
    end
  end

  def setup
    super
    store_graphs.work.write_intent(title: "Alpha")
    store_graphs.work.activate_intent("1")
  end

  def writer(clock) = Plastic::Graph::Work::Driver::Writer.new(store_graphs.databases, store_graphs.retrieval, clock:)

  def rival_claims_it = store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE drivers SET session_id = 's-3'") }

  def test_a_claim_taken_by_another_session_after_the_read_is_held_not_taken
    writer(Struct.new(:now).new(START)).claim(intent_id: "1", by: "s-1", mode: "auto")

    status, holder, = writer(RacingClock.new(START + (16 * 60)) { rival_claims_it }).claim(intent_id: "1", by: "s-2", mode: "auto")

    assert_equal [:held, "s-3"], [status, holder]
  end
end
