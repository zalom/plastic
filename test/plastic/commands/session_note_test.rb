# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/session_note"

class SessionNoteTest < Plastic::TestCase
  fixtures :empty

  def call(*args, env: {}) = plastic("session", "note", *args, env:, table: Plastic::CLI::TABLE)

  def test_the_note_is_written_to_the_session_row
    result = call("stopped", "after", "Beta", env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal "stopped after Beta", store_graphs.retrieval.session("s-1").note
    assert_includes result.out, "1 session and 1 routine run in local.db"
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
