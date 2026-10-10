# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/cli/screen"

class ScreenAnswerTest < Plastic::TestCase
  Screen = Plastic::CLI::Screen

  def choices = %w[claude codex cursor].map { |label| Screen::Choice.new(label:, chosen: false) }

  def answer(text) = Screen::Answer.new(choices).call(text)

  def refusal(text) = assert_raises(Plastic::CLI::Command::Usage) { answer(text) }.message

  def test_numbers_pick_those_items_in_list_order
    assert_equal Screen::Chosen.new(labels: %w[claude cursor]), answer(" 3, 1 ")
  end

  def test_a_repeated_number_picks_its_item_once
    assert_equal Screen::Chosen.new(labels: %w[codex]), answer("2,2")
  end

  def test_a_picks_every_item
    assert_equal Screen::Chosen.new(labels: %w[claude codex cursor]), answer("A")
  end

  def test_q_leaves_with_no_change
    assert_equal Screen::Left.new, answer("q")
  end

  def test_an_unknown_number_is_refused_with_the_valid_ones
    assert_includes refusal("1,7"), "no choice 7; the choices are 1, 2, 3"
  end

  def test_zero_is_an_unknown_number
    assert_includes refusal("0"), "no choice 0"
  end

  def test_an_unknown_word_is_refused_with_the_grammar
    assert_includes refusal("1,x"), Screen::Answer::GRAMMAR
  end

  def test_an_empty_answer_is_refused_with_the_grammar
    assert_includes refusal(" "), Screen::Answer::GRAMMAR
  end
end
