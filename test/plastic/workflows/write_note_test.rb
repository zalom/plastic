# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/write_note"

class WriteNoteTest < Plastic::TestCase
  def note(session)
    run_workflow(Plastic::Workflows::WriteNote, harness: scoped_harness(session:), graphs: Plastic::Graph.open(home: @plastic_home, store: "global", session:),
      text: "tests first")
  end

  def test_the_note_is_written_on_the_session_and_printed
    store_graphs.work.open_session("s-1", harness: "claude", directory: @home)

    outcome, context = note("s-1")

    assert_equal [:done, ["note: tests first"]], [outcome, context.printed]
    assert_equal "tests first", store_graphs.databases[:local].row("SELECT note FROM sessions WHERE session_id = 's-1'").fetch("note")
  end

  def test_a_call_with_no_session_fails_the_call
    assert_equal "code_write_note, gate: the call names no session; set PLASTIC_SESSION", note(nil).first.message
  end
end
