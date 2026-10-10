# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/cli/screen"

class ScreenNumberedListTest < Plastic::TestCase
  Screen = Plastic::CLI::Screen

  def choices = [Screen::Choice.new(label: "claude", chosen: true), Screen::Choice.new(label: "codex", chosen: false)]

  def listed(output_class)
    out = StringIO.new
    output = output_class.new(out:, err: StringIO.new)
    outcome = Screen::NumberedList.new(output).call("Which harnesses?", choices, command: "plastic init")
    output.flush
    [outcome, out.string]
  end

  def test_the_list_numbers_each_item_and_marks_the_preselected
    _, text = listed(Plastic::CLI::TextOutput)

    assert_includes text, "1  [x] claude"
    assert_includes text, "2  [ ] codex"
    assert_includes text, "Which harnesses?"
  end

  def test_the_list_says_the_answer_grammar
    _, text = listed(Plastic::CLI::TextOutput)

    assert_includes text, Screen::Answer::GRAMMAR
  end

  def test_next_carries_the_answer_placeholder
    _, text = listed(Plastic::CLI::TextOutput)

    assert_includes text, "next: plastic init <answer>"
    assert_match(/because: .*ask the person/, text)
  end

  def test_the_listed_outcome_stops_the_call
    outcome, = listed(Plastic::CLI::TextOutput)

    assert_equal Screen::Listed.new, outcome
  end

  def test_the_json_list_is_one_document
    _, text = listed(Plastic::CLI::JsonOutput)
    document = JSON.parse(text)

    assert_equal ["1  [x] claude", "2  [ ] codex"], document.dig("result", "choices")
    assert_equal "plastic init <answer>", document["next"]
  end
end
