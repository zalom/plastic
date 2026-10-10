# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/cli/screen"

class ScreenTerminalListTest < Plastic::TestCase
  Screen = Plastic::CLI::Screen
  Keys = Class.new(StringIO) { def wait_readable(*) = true }
  DOWN = "\e[B"

  def choices = %w[claude codex cursor].each_with_index.map { |label, index| Screen::Choice.new(label:, chosen: index.zero?) }

  def pressed(keys)
    prompt = Screen::TerminalList.prompt(Keys.new(keys), StringIO.new, env: { "TTY_TEST" => true })
    Screen::TerminalList.new(prompt).call("Which harnesses?", choices)
  end

  def test_enter_keeps_the_preselected_items
    assert_equal Screen::Chosen.new(labels: %w[claude]), pressed("\r")
  end

  def test_space_toggles_the_item_under_the_cursor
    assert_equal Screen::Chosen.new(labels: %w[claude codex]), pressed("#{DOWN} \r")
  end

  def test_a_preselected_item_can_be_toggled_off
    assert_equal Screen::Chosen.new(labels: []), pressed(" \r")
  end

  def test_ctrl_c_leaves_with_no_change
    assert_equal Screen::Left.new, pressed("\u0003")
  end
end
