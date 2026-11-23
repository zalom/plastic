# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentReportMandatoryTest < Plastic::TestCase
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

  def change_report
    write("#{retrieval.intent("1").dir}/#{REPORT}", "<p>changed</p>\n")
    sync_up
  end

  def test_a_report_that_becomes_mandatory_keeps_one_line
    call
    seed_config(@plastic_home, MANDATORY)
    change_report
    call

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT} (mandatory)\n", outcome
  end

  def test_a_report_that_stops_being_mandatory_keeps_one_line
    seed_config(@plastic_home, MANDATORY)
    call
    seed_config(@plastic_home, NOT_MANDATORY)
    change_report
    call

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}\n", outcome
  end

  def test_an_older_asked_line_stays_when_the_mandatory_setting_changes
    older = "#{OUTCOME}\n## Reports\n\n- #{REPORT}, asked: \"the page\"\n- #{REPORT}\n"
    write("#{retrieval.intent("1").dir}/outcome.md", older)
    sync_up
    seed_config(@plastic_home, MANDATORY)
    call

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}, asked: \"the page\"\n- #{REPORT} (mandatory)\n", outcome
  end

  def test_a_changed_report_with_the_same_setting_keeps_its_one_line
    call
    change_report
    call

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}\n", outcome
  end

  def test_an_intent_with_no_outcome_gets_the_mandatory_line_only
    intent = open_intent("Beta")
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
    seed_config(@plastic_home, MANDATORY)
    plastic("intent", "report", intent.intent_id, REPORT, table: Plastic::CLI::TABLE)

    assert_equal "# Outcome\n\n## Reports\n\n- #{REPORT} (mandatory)\n", retrieval.fetch(intent.intent_id, "outcome.md").body
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
end
