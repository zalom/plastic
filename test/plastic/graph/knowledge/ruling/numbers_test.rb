# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/ruling/numbers"

class RulingNumbersTest < Minitest::Test
  Numbers = Plastic::Graph::Knowledge::Ruling::Numbers

  def test_the_next_whole_number_follows_the_highest_one_held
    assert_equal "D11", Numbers.new(["D2", "D10 an old line", "D3.4"]).next_whole
  end

  def test_the_first_decision_of_an_intent_is_d1
    assert_equal ["D1", "D1.1"], [Numbers.new([]).next_whole, Numbers.new([]).next_addition("D1")]
  end

  def test_the_next_addition_follows_the_highest_addition_of_its_decision
    assert_equal "D1.4", Numbers.new(["D1", "D1.3: an old line", "D2.7", "D10.9"]).next_addition("D1")
  end

  def test_a_word_that_only_begins_like_an_id_holds_no_number
    assert_equal "D1", Numbers.new(["D7r First token", "D9a", "D4.1.2", "Done"]).next_whole
  end

  def test_only_a_whole_decision_is_whole
    assert_equal [true, false, false], %w[D1 D1.1 D1a].map { |id| Numbers.whole?(id) }
  end
end
