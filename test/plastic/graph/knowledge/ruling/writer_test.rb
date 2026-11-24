# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRulingWriterTest < Plastic::TestCase
  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @graphs.work.write_intent(title: "Alpha")
  end

  def writer = Plastic::Graph::Knowledge::Ruling::Writer.new(@graphs.databases, @graphs.retrieval, session: "s-1", clock: FixedClock::CLOCK)

  def links = @graphs.retrieval.links("1/D2").map { |link| [link.from_ref, link.to_ref, link.kind] }

  def test_each_ruling_takes_the_next_d_id_and_the_session
    first = writer.add_ruling(intent_id: "1", text: "Ship it")
    second = writer.add_ruling(intent_id: "1", text: "Wait")

    assert_equal [%w[D1 s-1], %w[D2 s-1]], [first, second].map { |ruling| [ruling.id, ruling.session_id] }
  end

  def test_a_leading_copy_of_the_rulings_own_id_is_dropped
    texts = ["D1 Ship it", "D2: Wait", "D3. Hold", "D4 - Go"].map { |text| writer.add_ruling(intent_id: "1", text:).text }

    assert_equal %w[Ship\ it Wait Hold Go], texts
  end

  def test_another_id_at_the_start_and_an_id_inside_a_word_are_kept
    texts = ["D7 is the one to read", "D20 runs later", "D3x stays"].map { |text| writer.add_ruling(intent_id: "1", text:).text }

    assert_equal ["D7 is the one to read", "D20 runs later", "D3x stays"], texts
  end

  def test_a_text_that_is_only_the_id_is_kept
    assert_equal "D1", writer.add_ruling(intent_id: "1", text: "D1").text
  end

  def test_a_ruling_that_supersedes_another_writes_the_link
    writer.add_ruling(intent_id: "1", text: "Ship it")
    ruling = writer.add_ruling(intent_id: "1", text: "Wait", supersedes: "1/D1")

    assert_equal "D1", ruling.supersedes
    assert_equal [["1/D2", "1/D1", "supersedes"]], links
  end

  def test_a_ruling_that_supersedes_a_missing_one_is_refused_and_writes_nothing
    assert_nil writer.add_ruling(intent_id: "1", text: "Wait", supersedes: "D9")
    assert_empty @graphs.retrieval.rulings("1")
  end
end
