# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/session/note"

class SessionNoteCaseTest < Plastic::TestCase
  def hook_start(source) = plastic("hook", "start", input: JSON.generate(source:), env: SESSION, table: Plastic::CLI::TABLE)

  def note(*words, env: SESSION) = plastic("session", "note", *words, env:, table: Plastic::CLI::TABLE)

  def resumed_note_lines = hook_start("clear").out.lines(chomp: true).grep(/\Anote: /)

  def test_a_note_prints_the_text_and_the_next_start_of_the_session_reads_it_back
    hook_start("startup")

    assert_case note("stopped", "after", "Beta"), code: 0, out: ["note: stopped after Beta"]
    assert_equal ["note: stopped after Beta"], resumed_note_lines
  end

  def test_a_second_note_replaces_the_first_in_what_the_next_start_reads_back
    hook_start("startup")
    note("first")

    assert_case note("second"), code: 0, out: ["note: second"]
    assert_equal ["note: second"], resumed_note_lines
  end

  def test_a_call_with_no_text_exits_2_and_leaves_no_note_to_read_back
    hook_start("startup")

    assert_case note, code: 2, out: "", err: ["missing TEXT"]
    assert_empty resumed_note_lines
  end

  def test_a_call_that_names_no_session_exits_1_and_says_to_set_the_session
    assert_case note("stopped", "after", "Beta", env: {}), code: 1, out: "", err: ["the call names no session; set PLASTIC_SESSION"]
  end
end

class SessionNoteTest < Plastic::TestCase
  fixtures :empty

  def call(*args, env: {}) = plastic("session", "note", *args, env:, table: Plastic::CLI::TABLE)

  def test_the_note_is_written_to_the_session_row
    result = call("stopped", "after", "Beta", env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal "stopped after Beta", store_graphs.retrieval.session("s-1").note
    assert_includes result.out, "1 session in plastic.db"
  end

  def test_the_run_of_the_call_is_kept_for_a_resume
    call("stopped", env: { "PLASTIC_SESSION" => "s-1" })

    assert_includes store_graphs.databases[:local].rows("SELECT tool FROM command_runs").map { |row| row.fetch("tool") }, "session note"
  end

  def test_a_second_note_replaces_the_first_with_no_new_row
    call("first", env: { "PLASTIC_SESSION" => "s-1" })
    call("second", env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal ["second"], store_graphs.databases[:local].rows("SELECT note FROM sessions WHERE session_id = 's-1'").map { |row| row.fetch("note") }
  end

  def test_a_call_with_no_session_fails
    result = call("stopped", env: {})

    assert_equal 1, result.code
  end
end
