# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/end"

class EndTest < Plastic::TestCase
  fixtures :empty

  def call(*args, env: { "PLASTIC_SESSION" => "s-1" }, input: "{}")
    plastic("hook", "end", *args, input:, env:, table: Plastic::CLI::TABLE)
  end

  CLAUDE = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze

  def start_claude_session = plastic("hook", "start", input: JSON.generate(source: "startup"), env: CLAUDE, table: Plastic::CLI::TABLE)

  def session_row
    session = store_graphs.retrieval.session("s-1")
    [session.harness, !session.last_turn_at.nil?, session.end_reason]
  end

  def test_end_sets_the_reason_and_not_the_turn
    start_claude_session
    result = call(input: JSON.generate(reason: "clear"), env: CLAUDE)

    assert_call result, code: 0, out: "", err: ""
    assert_equal ["claude-code", false, "clear"], session_row
  end

  def test_end_sets_the_end_time
    call(input: JSON.generate(reason: "logout"))

    refute_nil store_graphs.retrieval.session("s-1").ended_at
  end

  def test_a_codex_session_end_event_ends_the_row_it_names
    event = { session_id: "x-1", transcript_path: "/u/.codex/sessions/r.jsonl", cwd: @home, hook_event_name: "SessionEnd", reason: "other" }
    call(input: JSON.generate(event), env: {})

    assert_equal "other", store_graphs.retrieval.session("x-1").end_reason
  end

  def test_end_takes_no_harness_option
    start_claude_session

    assert_call call("--harness", "codex", env: CLAUDE, input: JSON.generate(reason: "logout")), code: 0, err: "plastic: invalid option: --harness\nplastic hook end\n"
    assert_equal ["claude-code", false, nil], session_row
  end

  def test_a_call_with_no_session_prints_one_stderr_line
    start_claude_session

    assert_call call(env: {}), code: 0, err: "plastic hook: the event names no session; nothing recorded\n"
    assert_equal ["claude-code", false, nil], session_row
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
