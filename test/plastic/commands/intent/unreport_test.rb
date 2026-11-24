# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentUnreportTest < Plastic::TestCase
  REPORT = "resources/output/reports/page.html"
  MOVED = "resources/tmp/page.html"
  PAGE = "<p>page</p>\n"
  OUTCOME = "# Outcome\n\nDelivered.\n"
  REASON = "a dry run, recorded by mistake"

  def call(*args) = plastic("intent", *args, table: Plastic::CLI::TABLE)

  def unreport(*args) = call("unreport", "1", REPORT, "--reason", REASON, *args)

  def dir = retrieval.intent("1").dir

  def lines = store_database.rows("SELECT kind, path, text FROM work_log WHERE kind IN ('reported', 'removed')").map(&:values)

  # The rows that hold the report: its documents, its head and its printed record.
  def rows
    store = store_database
    [*%w[documents document_heads].map { |table| store.rows("SELECT path FROM #{table} WHERE intent_id = '1' AND path = :path", path: REPORT).size },
      store.rows("SELECT path FROM printed WHERE path = :path", path: "#{dir}/#{REPORT}").size]
  end

  def outcome = retrieval.fetch("1", "outcome.md").body

  def setup
    super
    open_intent
    write("#{dir}/outcome.md", OUTCOME)
    write("#{dir}/#{REPORT}", PAGE)
    sync_up
    call("report", "1", REPORT)
  end

  def test_the_removal_drops_the_rows_the_file_and_the_outcome_line
    result = unreport

    assert_equal [0, [0, 0, 0], false, OUTCOME], [result.code, rows, File.exist?(store_path("#{dir}/#{REPORT}")), outcome]
    assert_includes result.out, "removed: #{REPORT}"
  end

  def test_the_printed_outcome_no_longer_lists_the_report
    unreport

    assert_equal OUTCOME, File.read(store_path("#{dir}/outcome.md"))
  end

  def test_the_option_to_tmp_moves_the_file_and_drops_its_rows
    result = unreport("--to-tmp")

    assert_equal [0, [0, 0, 0], false, PAGE], [result.code, rows, File.exist?(store_path("#{dir}/#{REPORT}")), File.read(store_path("#{dir}/#{MOVED}"))]
    assert_includes result.out, "moved: #{REPORT} to #{MOVED}"
  end

  def test_the_work_log_keeps_the_reported_line_and_gains_the_removed_line
    unreport

    assert_equal [["reported", REPORT, ""], ["removed", REPORT, REASON]], lines
  end

  def test_the_recorded_reports_no_longer_count_the_report
    unreport

    refute Plastic::Graph::Knowledge::Reports.none.recorded_from(store_database).listed?("1", REPORT)
  end

  def test_a_report_recorded_again_after_its_removal_is_a_new_record
    unreport
    write("#{dir}/#{REPORT}", PAGE)
    result = call("report", "1", REPORT)

    assert_includes result.out, "reported: #{REPORT}"
    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}\n", outcome
  end

  def test_a_path_with_no_record_exits_1_and_writes_nothing
    result = call("unreport", "1", "resources/output/reports/other.html", "--reason", REASON)

    assert_equal [1, [1, 1, 1], 1], [result.code, rows, lines.size]
  end

  def test_a_removed_report_cannot_be_removed_twice
    unreport

    assert_equal [1, 2], [unreport.code, lines.size]
  end

  def test_the_reason_is_required
    assert_equal [2, [1, 1, 1]], [call("unreport", "1", REPORT).code, rows]
  end

  def test_a_file_already_in_tmp_stops_the_move_and_writes_nothing
    write("#{dir}/#{MOVED}", "other\n")

    assert_equal [1, [1, 1, 1], PAGE], [unreport("--to-tmp").code, rows, File.read(store_path("#{dir}/#{REPORT}"))]
  end

  def test_the_dry_run_changes_nothing
    assert_equal [0, [1, 1, 1], 1, PAGE], [unreport("--dry-run").code, rows, lines.size, File.read(store_path("#{dir}/#{REPORT}"))]
  end
end
