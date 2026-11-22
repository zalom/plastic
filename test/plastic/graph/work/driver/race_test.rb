# frozen_string_literal: true

require_relative "../../../../test_helper"

# Two sessions that read the intent as free and write at the same moment: the guarded write lets one of them win.
class WorkDriverRaceTest < Plastic::TestCase
  Clock = Struct.new(:now)

  # A writer that reads the intent as free once, as a session does that reads just before another one writes.
  class StaleWriter < Plastic::Graph::Work::Driver::Writer
    def holder(intent_id)
      @reads = @reads.to_i + 1
      (@reads == 1) ? nil : super
    end
  end

  def setup
    super
    @clock = Clock.new(Time.utc(2026, 11, 23, 8, 0, 0))
    store_graphs.work.write_intent(title: "Alpha")
    store_graphs.work.activate_intent("1")
  end

  def test_a_claim_lost_to_a_session_that_wrote_first_is_held_by_that_session
    Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-3", clock: @clock).work.drive_intent(intent_id: "1", by: "s-3")
    writer = StaleWriter.new(store_graphs.databases, retrieval, clock: @clock)

    assert_equal [:held, "s-3", nil], writer.claim(intent_id: "1", by: "s-2")
  end
end
