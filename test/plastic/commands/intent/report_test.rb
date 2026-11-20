# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentReportTest < Plastic::TestCase
  include ConfigHomes

  REPORT = "resources/output/reports/page.html"
  OUTCOME = "# Outcome\n\nDelivered.\n"

  def call(*args) = plastic("intent", "report", *args, table: Plastic::CLI::TABLE)

  def reported = store_database.rows("SELECT intent_id, path, text, sha256 FROM work_log WHERE kind = 'reported'").map(&:values)

  def outcome = retrieval.fetch("1", "outcome.md").body

  def setup
    super
    intent = open_intent
    write("#{intent.dir}/outcome.md", OUTCOME)
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
  end

  def test_a_report_records_with_no_words
    result = call("1", REPORT)

    assert_equal [0, ""], [result.code, result.err]
    assert_equal [["1", REPORT, "", Digest::SHA256.hexdigest("<p>page</p>\n")]], reported
  end

  def test_the_asked_option_is_a_usage_error_and_writes_nothing
    result = call("1", REPORT, "--asked", "delivery page")

    assert_equal [2, [], OUTCOME], [result.code, reported, outcome]
  end

  def test_a_closed_intent_exits_1_and_writes_nothing
    store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = '1'") }

    assert_equal [1, [], OUTCOME], [call("1", REPORT).code, reported, outcome]
  end

  def test_an_older_line_with_the_asked_words_stays_beside_the_new_line
    older = "#{OUTCOME}\n## Reports\n\n- resources/output/reports/old.html, asked: \"the old page\"\n"
    write("#{retrieval.intent("1").dir}/outcome.md", older)
    sync_up
    call("1", REPORT)

    assert_equal "#{older}- #{REPORT}\n", outcome
  end

  def test_a_missing_file_exits_1_and_writes_nothing
    result = call("1", "resources/output/reports/gone.html")

    assert_equal [1, []], [result.code, reported]
  end

  def test_the_outcome_gets_one_line_under_a_reports_heading
    call("1", REPORT)

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}\n", outcome
  end

  def test_a_second_record_of_the_same_path_writes_nothing
    call("1", REPORT)
    result = call("1", REPORT)

    assert_equal [0, 1], [result.code, reported.size]
    assert_equal 1, outcome.scan(REPORT).size
  end

  def test_a_mandatory_report_records_with_no_words
    seed_config(@plastic_home, "global:\n  reports:\n    mandatory: [page.html]\n")
    result = call("1", REPORT)

    assert_equal [0, [["1", REPORT, "mandatory"]]], [result.code, reported.map { |row| row.first(3) }]
    assert_includes outcome, "- #{REPORT} (mandatory)\n"
  end

  def test_a_recorded_report_is_read_by_the_next_sync
    call("1", REPORT)
    plastic("sync", "up", table: Plastic::CLI::TABLE)

    assert_includes store_database.rows("SELECT path FROM documents").map { |row| row["path"] }, REPORT
  end

  def test_a_report_recorded_on_another_machine_counts_as_recorded
    store_database.transaction do |batch|
      batch.put(:work_log, { intent_id: "1", position: 90, at: STAMP, phase: "", node: "", session_id: "s", kind: "reported", path: REPORT, sha256: "", text: "on another machine", origin_id: "other-machine" })
    end

    assert_equal [0, OUTCOME], [call("1", REPORT).code, outcome]
  end

  def test_an_unknown_intent_exits_1_and_writes_nothing
    assert_equal [1, []], [call("9", REPORT).code, reported]
  end

  def test_an_intent_with_no_outcome_gets_one_with_the_reports_section
    intent = open_intent("Beta")
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
    call(intent.intent_id, REPORT)

    assert_equal "# Outcome\n\n## Reports\n\n- #{REPORT}\n", retrieval.fetch(intent.intent_id, "outcome.md").body
  end
end
