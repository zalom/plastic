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
end
