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

  def rulings = @graphs.retrieval.rulings("1").sort_by(&:id).map { |ruling| [ruling.id, ruling.text] }

  # A ruling written through the work graph, so its ruled line is in the work log.
  def ruled(text, **options) = @graphs.work.add_ruling(intent_id: "1", text:, **options)

  def test_an_addition_takes_the_next_number_under_its_decision
    writer.add_ruling(intent_id: "1", text: "Ship it")
    first = writer.add_ruling(intent_id: "1", text: "On Fridays", adds: "D1")
    second = writer.add_ruling(intent_id: "1", text: "Before noon", adds: "1/D1")

    assert_equal %w[D1.1 D1.2], [first, second].map(&:id)
  end

  def test_a_whole_number_follows_the_highest_whole_one_and_skips_the_additions
    writer.add_ruling(intent_id: "1", text: "Ship it")
    writer.add_ruling(intent_id: "1", text: "On Fridays", adds: "D1")

    assert_equal "D2", writer.add_ruling(intent_id: "1", text: "Wait").id
  end

  def test_an_addition_to_a_missing_decision_or_to_an_addition_is_refused_and_writes_nothing
    writer.add_ruling(intent_id: "1", text: "Ship it")
    writer.add_ruling(intent_id: "1", text: "On Fridays", adds: "D1")

    assert_equal [nil, nil], [writer.add_ruling(intent_id: "1", text: "Wait", adds: "D9"), writer.add_ruling(intent_id: "1", text: "Wait", adds: "D1.1")]
    assert_equal [["D1", "Ship it"], ["D1.1", "On Fridays"]], rulings
  end

  def test_a_rewrite_replaces_the_text_and_keeps_the_number
    writer.add_ruling(intent_id: "1", text: "Ship it")
    writer.add_ruling(intent_id: "1", text: "Wait")

    rewritten = writer.add_ruling(intent_id: "1", text: "D1: Ship it on Monday", rewrites: "D1")

    assert_equal ["D1", "Ship it on Monday"], [rewritten.id, rewritten.text]
    assert_equal [["D1", "Ship it on Monday"], ["D2", "Wait"]], rulings
  end

  def test_a_rewrite_removes_the_additions_of_its_decision_and_their_links
    writer.add_ruling(intent_id: "1", text: "Ship it")
    writer.add_ruling(intent_id: "1", text: "On Fridays", adds: "D1")
    @graphs.work.add_link(from_ref: "1/D1.1", to_ref: "1", kind: "cites")

    writer.add_ruling(intent_id: "1", text: "Ship it on Monday", rewrites: "D1")

    assert_equal [[["D1", "Ship it on Monday"]], []], [rulings, @graphs.retrieval.links("1/D1.1")]
  end

  def test_a_rewrite_of_a_missing_decision_or_of_an_addition_is_refused_and_writes_nothing
    writer.add_ruling(intent_id: "1", text: "Ship it")
    writer.add_ruling(intent_id: "1", text: "On Fridays", adds: "D1")

    assert_equal [nil, nil], [writer.add_ruling(intent_id: "1", text: "Wait", rewrites: "D9"), writer.add_ruling(intent_id: "1", text: "Wait", rewrites: "D1.1")]
    assert_equal [["D1", "Ship it"], ["D1.1", "On Fridays"]], rulings
  end

  def test_a_whole_number_a_removed_decision_held_is_not_used_again
    ruled("Ship it")
    ruled("Wait")
    @graphs.databases.fetch(:store).transaction { |batch| batch.remove(:rulings, intent_id: "1", id: "D2") }

    assert_equal "D3", ruled("Hold").id
  end

  def test_an_addition_number_a_rewrite_removed_is_not_used_again
    ruled("Ship it")
    ruled("On Fridays", adds: "D1")
    ruled("On Mondays", adds: "D1")
    ruled("Ship it on Monday", rewrites: "D1")

    assert_equal "D1.3", ruled("Before noon", adds: "D1").id
  end
end
