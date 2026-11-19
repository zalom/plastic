# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeReportsTest < Plastic::TestCase
  REPORT = "resources/output/reports/page.html"

  def log_line(intent_id, kind, path)
    store_database.transaction do |batch|
      batch.put(:work_log, { intent_id:, position: 1, at: STAMP, phase: "", node: "", session_id: "s", kind:, path:, sha256: "", text: "asked" })
    end
  end

  def test_the_recorded_reports_are_the_reported_lines_of_the_store
    open_intent
    log_line("1", "reported", REPORT)
    reports = Plastic::Graph::Knowledge::Reports.none.recorded_from(store_database)

    assert_equal [true, false], [reports.include?("1", REPORT), reports.include?("2", REPORT)]
  end

  def test_a_line_of_another_kind_records_no_report
    open_intent
    log_line("1", "noted", REPORT)

    refute Plastic::Graph::Knowledge::Reports.none.recorded_from(store_database).include?("1", REPORT)
  end

  def test_the_mandatory_names_come_from_a_list_or_a_comma_value
    assert_equal [%w[a.md b.html], %w[a.md b.html], []], [%w[a.md b.html], " a.md, b.html", nil].map { |value| Plastic::Graph::Knowledge::Reports.named(value) }
  end

  def test_a_mandatory_name_is_a_path_inside_the_reports_folder
    reports = Plastic::Graph::Knowledge::Reports.new(mandatory: %w[delivery/summary.md])

    assert_equal [true, false], %w[resources/output/reports/delivery/summary.md resources/output/reports/summary.md].map { |rel| reports.mandatory?(rel) }
  end

  def test_no_report_is_recorded_when_no_store_is_bound
    refute Plastic::Graph::Knowledge::Reports.new(mandatory: []).include?("1", REPORT)
  end
end
