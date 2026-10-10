# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/screen"

class ScreenTest < Plastic::TestCase
  Screen = Plastic::CLI::Screen
  Terminal = Class.new(StringIO) { def tty? = true }
  Prompt = Struct.new(:picked) do
    def multi_select(*, **) = picked
  end

  def choices = [Screen::Choice.new(label: "claude", chosen: true), Screen::Choice.new(label: "codex", chosen: false)]

  def screen(input: Terminal.new, stream: Terminal.new, output_class: Plastic::CLI::TextOutput)
    output = output_class.new(out: StringIO.new, err: StringIO.new)
    Screen.new(input:, stream:, output:, prompt: ->(_input, _stream) { Prompt.new(%w[codex]) })
  end

  def test_two_terminal_streams_open_the_terminal_list
    assert_equal Screen::Chosen.new(labels: %w[codex]), screen.ask("Which?", choices, command: "plastic init")
  end

  def test_a_pipe_is_listed
    assert_equal Screen::Listed.new, screen(input: StringIO.new).ask("Which?", choices, command: "plastic init")
  end

  def test_a_piped_output_is_listed
    refute_predicate screen(stream: StringIO.new), :terminal?
  end

  def test_json_is_listed_on_a_terminal
    refute_predicate screen(output_class: Plastic::CLI::JsonOutput), :terminal?
  end

  def test_a_stream_that_cannot_say_is_listed
    refute_predicate screen(input: Object.new), :terminal?
  end

  def test_the_answer_reads_against_the_choices
    assert_equal Screen::Chosen.new(labels: %w[claude codex]), screen.answer("a", choices)
  end

  def test_the_asking_scope_carries_the_screen
    environment = Plastic::CLI::Command::Environment.new(env: {}, input: StringIO.new, out: StringIO.new,
      err: StringIO.new, home: Dir.tmpdir, directory: Dir.tmpdir)
    scope = Plastic::Commands::AskingScope.for(environment, slug: nil, output: Plastic::CLI::TextOutput.new(out: StringIO.new, err: StringIO.new))

    assert_instance_of Screen, scope.screen
  end
end
