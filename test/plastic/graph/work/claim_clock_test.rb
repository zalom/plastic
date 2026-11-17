# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/next_pick"

# Every reader of a claim judges its lapse by the time it is given, never by the clock of the machine.
class WorkClaimClockTest < Plastic::TestCase
  ROOT = File.expand_path("../../../..", __dir__)

  READERS = %w[lib/plastic/workflows/code/auto/pick.rb lib/plastic/graph/work/next_pick.rb lib/plastic/workflows/delivery_ownership.rb
    lib/plastic/hooks/stop_gate.rb lib/plastic/hooks/recap.rb].freeze

  def test_no_reader_of_a_claim_reads_the_machine_clock
    assert_empty(READERS.select { |path| File.read(File.join(ROOT, path)).include?("Time.now") })
  end

  def test_a_context_tells_the_time_of_its_clock
    clock = Struct.new(:now).new(Time.utc(2026, 11, 17, 8, 0, 0))
    context = Plastic::Context.new(declared: [], facts: {}, graphs: store_graphs, clock:)

    assert_equal clock.now, context.now
  end

  def hold_first_of_two
    2.times { |index| store_graphs.work.write_intent(title: "Intent #{index}") }
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
  end

  def test_the_pick_of_the_next_intent_judges_a_claim_by_the_time_it_is_given
    hold_first_of_two
    picks = ->(now) { Plastic::Graph::Work::NextPick.new(retrieval, "s-1", now:).candidates.map(&:intent_id) }

    assert_equal [["1"], %w[1 2]], [picks.call(Time.now), picks.call(Time.now + 3600)]
  end
end
