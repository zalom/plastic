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
    texts = ["D1 Ship it", "D2: Wait", "D3. Hold", "D4 - Go", "D5 D5: Run"].map { |text| writer.add_ruling(intent_id: "1", text:).text }

    assert_equal %w[Ship\ it Wait Hold Go Run], texts
  end

  def own_text(text) = Plastic::Graph::Knowledge::Ruling::Writer.own_text(text, "D1")

  def test_a_label_with_any_dash_or_a_space_before_a_capital_a_quote_or_a_bracket_is_dropped
    texts = ["D1 — Ship it", "D1 – Ship it", "D1—Ship it", "D1 D1 — Ship it", "D1: D1: Ship it", "D1 `ship` it", "D1 (Q2) Ship it", "D1 C16 holds"]

    assert_equal ["Ship it", "Ship it", "Ship it", "Ship it", "Ship it", "`ship` it", "(Q2) Ship it", "C16 holds"], texts.map { |text| own_text(text) }
  end

  def test_an_id_that_starts_a_range_or_a_list_is_kept
    texts = ["D1 through D8 are binding", "D1 to D9 stand", "D1 and D2 hold", "D1..D6: ruled", "D1 / D1a: a skill", "D1, D2 hold",
      "D1 D8 hold", "D1-D8 hold", "D1 – D8 hold", "D1 b, D2 b", "D1 docx tooling: Sablon", "D1 .env stays", "D1.5 holds"]

    assert_equal texts, texts.map { |text| own_text(text) }
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
