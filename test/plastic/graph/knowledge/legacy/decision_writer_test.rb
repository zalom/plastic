# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyDecisionWriterTest < Plastic::TestCase
  def write_decision
    counts = Hash.new(0)
    decision = { intent_id: "1", rulings: [["D1", "Ship it"]], source: ["notes.md"], chain: ["3"] }
    Plastic::Graph::Knowledge::Legacy::DecisionWriter.new(store_graphs.databases, counts, clock: FixedClock::CLOCK).call([decision])
    counts
  end

  def test_writing_decisions_counts_the_rulings_and_links
    assert_equal({ rulings: 1, links: 2 }, write_decision)
  end

  def test_writing_decisions_writes_the_ruling_rows
    write_decision

    assert_equal ["Ship it"], retrieval.rulings("1").map(&:text)
  end

  def test_writing_decisions_writes_the_source_and_chain_links
    write_decision

    assert_equal [%w[1 notes.md source], %w[1 3 chain]], retrieval.links("1").map { |link| [link.from_ref, link.to_ref, link.kind] }
  end
end
