# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/end"

class EndTest < Plastic::TestCase
  fixtures :empty

  def call(*args, env: { "PLASTIC_SESSION" => "s-1" }, input: "{}")
    plastic("hook", "end", *args, input:, env:, table: Plastic::CLI::TABLE)
  end

  def test_end_sets_the_reason_and_not_the_turn
    call(input: JSON.generate(reason: "clear"))

    session = store_graphs.retrieval.session("s-1")

    assert_equal "clear", session.end_reason
    assert_nil session.last_turn_at
  end

  def test_end_sets_the_end_time
    call(input: JSON.generate(reason: "logout"))

    refute_nil store_graphs.retrieval.session("s-1").ended_at
  end

  def test_end_takes_no_harness_option
    assert_call call("--harness", "codex"), code: 0, err: "plastic: invalid option: --harness\nplastic hook end\n"
  end

  def test_a_call_with_no_session_prints_one_stderr_line
    assert_call call(env: {}), code: 0, err: "plastic hook: the event names no session; nothing recorded\n"
  end

  def test_help_prints_the_usage
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }, input: StringIO.new,
      out: StringIO.new, err: StringIO.new, home: @home, directory: @home)
    Plastic::CLI.bin_call(%w[help hook end], environment:, table: Plastic::CLI::TABLE)

    assert_equal "plastic hook end", environment.out.string.lines.first.chomp
  end

  def test_stop_takes_no_end_option
    result = plastic("hook", "stop", "--end", input: "{}", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_nil store_graphs.retrieval.session("s-1")&.end_reason
  end
end
