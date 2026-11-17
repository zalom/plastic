# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/predecessor_session"

class PredecessorSessionTest < Plastic::TestCase
  fixtures :empty

  def opened(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def predecessor(source: "startup", session: "s-2")
    Plastic::Hooks::PredecessorSession.new(opened(session).retrieval, session_id: session, source:, directory: @home)
  end

  def test_a_store_with_no_other_session_has_no_predecessor
    assert_nil predecessor.session
    assert_empty predecessor.lines
  end

  def test_the_latest_other_session_is_named_with_what_it_touched
    opened.work.open_session("s-1", harness: "claude-code", directory: @home)
    work = opened.work
    intent_id = work.write_intent(title: "Alpha").intent_id.tap { |id| work.print_intent(id) }
    work.end_session("s-1", reason: "clear")

    lines = predecessor.lines

    assert lines.first.match?(/\Aprevious session s-1 ended .* \(clear\)\z/)
    assert_includes lines, "touched: #{intent_id}"
  end

  def test_a_clear_reads_the_session_that_ended_in_its_directory
    opened.work.open_session("s-1", harness: "claude-code", directory: @home)
    opened.work.end_session("s-1", reason: "clear")

    assert_equal "s-1", predecessor(source: "clear").session.session_id
  end
end
