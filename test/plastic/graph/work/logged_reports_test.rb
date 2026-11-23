# frozen_string_literal: true

require_relative "../../../test_helper"

# The work writer records a report from the ReportFile value, not from an intent and a path.
class WorkLoggedReportsTest < Plastic::TestCase
  include ConfigHomes

  REPORT = "resources/output/reports/page.html"

  def reported = store_database.rows("SELECT intent_id, path, text FROM work_log WHERE kind = 'reported'").map(&:values)

  def setup
    super
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDelivered.\n")
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
  end

  def test_the_work_writer_records_the_report_file_value_it_is_given
    graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    file = Plastic::Graph::Knowledge::Intent::ReportFile.new(graphs.retrieval.intent("1"), REPORT)

    graphs.work.report_intent(file, "")

    assert_equal [["1", REPORT, ""]], reported
  end
end
