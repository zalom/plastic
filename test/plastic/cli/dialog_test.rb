# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/dialog"

class DialogTest < Plastic::TestCase
  Terminal = Class.new(StringIO) { def tty? = true }
  Output = Struct.new(:lines, :json) do
    def raw(text) = lines << text

    def json? = json
  end

  def dialog(input, json: false) = Plastic::CLI::Dialog.new(input:, output: Output.new([], json))

  def test_a_terminal_input_is_a_person
    assert dialog(Terminal.new).terminal?
  end

  def test_a_pipe_is_no_person
    refute dialog(StringIO.new).terminal?
  end

  def test_a_stream_that_cannot_say_it_is_a_terminal_is_no_person
    refute dialog(Object.new).terminal?
  end

  def test_json_output_is_never_asked_to_wait_for_a_person
    refute dialog(Terminal.new, json: true).terminal?
  end

  def test_a_known_answer_comes_back_lowercased
    assert_equal "up", dialog(Terminal.new(" UP \n")).choose("which?", choices: %w[up down])
  end

  def test_an_unknown_answer_is_asked_again_once
    asking = dialog(Terminal.new("what\ndown\n"))

    assert_equal ["down", ["which?", "which?"]], [asking.choose("which?", choices: %w[up down]), asking.output.lines]
  end

  def test_two_unknown_answers_come_back_as_nil
    assert_nil dialog(Terminal.new("a\nb\nup\n")).choose("which?", choices: %w[up down])
  end
end
