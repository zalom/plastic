# frozen_string_literal: true

require_relative "../../../test_helper"

# A report whose file did not change, after the reports.mandatory setting changed.
class IntentReportUnchangedTest < Plastic::TestCase
  include ConfigHomes

  REPORT = "resources/output/reports/page.html"
  OUTCOME = "# Outcome\n\nDelivered.\n"
  MANDATORY = "global:\n  reports:\n    mandatory: [page.html]\n"
  NOT_MANDATORY = "global:\n  reports:\n    mandatory: []\n"

  def call = plastic("intent", "report", "1", REPORT, table: Plastic::CLI::TABLE)

  def outcome = retrieval.fetch("1", "outcome.md").body

  def setup
    super
    intent = open_intent
    write("#{intent.dir}/outcome.md", OUTCOME)
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
  end

  def reported_count = store_database.rows("SELECT 1 FROM work_log WHERE kind = 'reported'").size

  def test_an_unchanged_report_that_becomes_mandatory_gets_its_line_rewritten
    call
    seed_config(@plastic_home, MANDATORY)
    result = call

    assert_equal [0, "#{OUTCOME}\n## Reports\n\n- #{REPORT} (mandatory)\n"], [result.code, outcome]
  end

  def test_an_unchanged_report_that_stops_being_mandatory_gets_its_plain_line_back
    seed_config(@plastic_home, MANDATORY)
    call
    seed_config(@plastic_home, NOT_MANDATORY)
    call

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}\n", outcome
  end

  def test_rewriting_the_line_of_an_unchanged_report_adds_no_log_line
    call
    seed_config(@plastic_home, MANDATORY)
    call

    assert_equal 1, reported_count
  end

  def test_rewriting_the_line_of_an_unchanged_report_says_so
    call
    seed_config(@plastic_home, MANDATORY)

    assert_includes call.out, "outcome line rewritten, no row and no log line"
  end

  def test_an_unchanged_report_with_the_right_line_says_nothing_was_written
    call

    assert_includes call.out, "nothing written"
  end

  def rows_of(path) = %w[documents document_heads].map { |table| store_database.rows("SELECT * FROM #{table} WHERE path = '#{path}'").map(&:values) }

  def test_rewriting_the_line_leaves_the_rows_of_the_report_as_they_were
    call
    before = rows_of(REPORT)
    seed_config(@plastic_home, MANDATORY)
    call

    assert_equal before, rows_of(REPORT)
  end

  def test_rewriting_the_line_gives_only_the_outcome_a_new_head
    call
    before = rows_of("outcome.md")
    seed_config(@plastic_home, MANDATORY)
    call

    refute_equal before, rows_of("outcome.md")
  end

  def test_a_changed_setting_writes_nothing_when_the_outcome_does_not_list_the_report
    write("#{retrieval.intent("1").dir}/outcome.md", OUTCOME)
    store_database.transaction { |batch| batch.write(:work_log, "INSERT INTO work_log (intent_id, position, at, phase, node, session_id, kind, path, sha256, text, origin_id) VALUES ('1', 99, '', '', '', '', 'reported', '#{REPORT}', '#{Digest::SHA256.hexdigest("<p>page</p>\n")}', '', 'other')") }
    seed_config(@plastic_home, MANDATORY)
    call

    assert_equal OUTCOME, outcome
  end
end
