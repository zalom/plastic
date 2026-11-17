# frozen_string_literal: true

require_relative "../../../../test_helper"

# The retry cap counts the runs after the last answer of the owner, not all the runs of the node.
class WorkNodeRetryCapTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def setup
    super
    @clock = Clock.new(START)
    @minute = 0
    store_graphs.work.write_intent(title: "Alpha")
    work.add_node(intent_id: "1", title: "Build", criterion: "it works")
  end

  def work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1", clock: @clock).work

  def claim
    @clock.now = START + ((@minute += 1) * 60)
    state, = work.claim_node(intent_id: "1", id: "n1", by: "s-1")
    work.release_node(intent_id: "1", id: "n1", by: "s-1") if state == :claimed
    state
  end

  def test_three_runs_cap_the_node
    3.times { claim }

    assert_equal :capped, claim
  end

  def test_the_cap_counts_only_the_runs_after_the_last_resolve
    4.times { claim }
    work.resolve_node(intent_id: "1", id: "n1", answer: "go on")

    assert_equal [:claimed, :claimed, :claimed, :capped], Array.new(4) { claim }
  end
end
