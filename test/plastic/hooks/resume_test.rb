# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/resume"

class ResumeTest < Plastic::TestCase
  fixtures :empty

  def call(source: nil, env: { "PLASTIC_SESSION" => "s-1" }, input: nil)
    body = input || JSON.generate(source ? { source: } : {})
    plastic("hook", "resume", input: body, env:, table: Plastic::CLI::TABLE)
  end

  def test_a_new_session_prints_the_new_line
    result = call

    assert_match(/\APlastic: a new session in store global\. Run plastic next before anything else\.\z/,
      result.out.lines.first.chomp)
  end

  def test_a_new_session_prints_the_previous_session_and_what_it_touched
    opened = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    opened.work.open_session("s-1", harness: "claude-code", directory: @home)
    intent_id = opened.work.write_intent(title: "Alpha").intent_id
    opened.work.print_intent(intent_id)
    opened.work.end_session("s-1", reason: "clear")

    result = call(env: { "PLASTIC_SESSION" => "s-2" })

    assert_match(/previous session s-1 ended .* \(clear\)/, result.out)
    assert_includes result.out, "touched: #{intent_id}"
  end

  def test_clear_prints_open_intents_and_the_note
    opened = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    intent_id = opened.work.write_intent(title: "Alpha").intent_id
    opened.work.print_intent(intent_id)
    opened.work.write_note("s-1", "stopped after Alpha")

    result = call(source: "clear")

    assert_includes result.out, "Plastic: the context was cleared"
    assert_includes result.out, "open: #{intent_id} Alpha (open)"
  end

  def test_clear_prints_the_intent_in_progress
    opened = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    intent_id = opened.work.write_intent(title: "Alpha").intent_id
    opened.work.print_intent(intent_id)

    result = call(source: "clear")

    assert_includes result.out, "in progress: #{intent_id} Alpha"
  end

  def test_compact_prints_savepoint_lines_and_the_note
    opened = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    intent_id = opened.work.write_intent(title: "Alpha").intent_id
    opened.work.print_intent(intent_id)
    opened.work.write_note("s-1", "note text")

    result = call(source: "compact")

    assert_includes result.out, "Plastic: the session was compacted"
    assert_includes result.out, "Opened: Alpha"
    assert_includes result.out, "note: note text"
  end

  def test_resume_writes_the_session_row
    call

    refute_nil store_graphs.retrieval.session("s-1")
  end

  def test_resume_source_prints_this_sessions_own_state
    result = call(source: "resume")

    assert_includes result.out, "Plastic: a resumed session"
  end

  def test_after_resume_the_stores_own_databases_are_ignored
    call

    assert_includes folder.read(".gitignore"), "*.db"
  end
end
