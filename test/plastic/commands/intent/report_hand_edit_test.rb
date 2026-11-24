# frozen_string_literal: true

require_relative "../../../test_helper"

# plastic intent report reads outcome.md from its rows, so a hand-written outcome.md that no row holds yet is refused,
# never overwritten.
class IntentReportHandEditTest < Plastic::TestCase
  include HandEditHelper

  REPORT = "resources/output/reports/page.html"
  BY_HAND = "# Outcome\n\nWritten by hand.\n"

  def call(*args) = plastic("intent", "report", *args, table: Plastic::CLI::TABLE)

  def reported = store_database.rows("SELECT path FROM work_log WHERE kind = 'reported'").map(&:values)

  def test_an_outcome_written_by_hand_that_no_row_holds_is_refused_and_keeps_its_text
    intent = open_intent
    path = "#{intent.dir}/outcome.md"
    write(path, BY_HAND)
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    result = call("1", REPORT)

    assert_refused(result, path)
    assert_equal [BY_HAND, [], nil], [File.read(store_path(path)), reported, retrieval.fetch("1", "outcome.md")]
  end

  def test_an_outcome_written_by_hand_after_its_print_is_refused_and_keeps_its_text
    intent = open_intent
    path = "#{intent.dir}/outcome.md"
    write(path, "# Outcome\n")
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
    store_graphs.work.print_intent("1")
    write(path, BY_HAND)
    result = call("1", REPORT)

    assert_refused(result, path)
    assert_equal [BY_HAND, []], [File.read(store_path(path)), reported]
  end
end
