# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentReportTest < Plastic::TestCase
  include ConfigHomes

  REPORT = "resources/output/reports/page.html"
  OUTCOME = "# Outcome\n\nDelivered.\n"
  SESSION = { "PLASTIC_SESSION" => "s-1" }.freeze

  def call(*args, env: {}) = plastic("intent", "report", *args, env:, table: Plastic::CLI::TABLE)

  def say(text, role: "user", store: "global", session_id: "s-9", intent_id: nil)
    Plastic::Graph::Work::Chat::Writer.new(store_graphs.databases.fetch(:local), store:, clock: Time)
      .record(session_id:, harness: nil, intent_id:, role:, text:)
  end

  def reported = store_database.rows("SELECT intent_id, path, text, sha256 FROM work_log WHERE kind = 'reported'").map(&:values)

  def outcome = retrieval.fetch("1", "outcome.md").body

  def setup
    super
    intent = open_intent
    write("#{intent.dir}/outcome.md", OUTCOME)
    write("#{intent.dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
  end

  def test_words_of_an_owner_message_of_the_store_record_the_report
    say("Please write the delivery page as html")
    result = call("1", REPORT, "--asked", "delivery page")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal [["1", REPORT, "delivery page", Digest::SHA256.hexdigest("<p>page</p>\n")]], reported
  end

  def test_the_words_match_without_regard_to_case
    say("Please write the Delivery Page")

    assert_equal 0, call("1", REPORT, "--asked", "delivery page").code
  end

  def test_an_owner_message_of_the_session_counts_in_another_store
    say("write the delivery page", store: "other", session_id: "s-1")

    assert_equal 0, call("1", REPORT, "--asked", "delivery page", env: SESSION).code
  end

  def test_words_in_no_owner_message_exit_3_and_write_nothing
    say("write the delivery page")
    result = call("1", REPORT, "--asked", "a summary nobody asked for")

    assert_equal [3, [], OUTCOME], [result.code, reported, outcome]
  end

  def test_an_owner_message_of_another_store_intent_and_session_does_not_count
    say("write the delivery page", store: "other", session_id: "s-9", intent_id: "9")

    assert_equal [3, []], [call("1", REPORT, "--asked", "delivery page", env: SESSION).code, reported]
  end

  def test_an_assistant_message_does_not_count
    say("I will write the delivery page", role: "assistant")

    assert_equal [3, []], [call("1", REPORT, "--asked", "delivery page").code, reported]
  end

  def test_a_report_with_no_words_and_no_mandatory_setting_exits_3
    assert_equal [3, []], [call("1", REPORT).code, reported]
  end

  def test_a_missing_file_exits_1_and_writes_nothing
    say("write the delivery page")
    result = call("1", "resources/output/reports/gone.html", "--asked", "delivery page")

    assert_equal [1, []], [result.code, reported]
  end

  def test_a_path_outside_the_reports_folder_exits_1_and_writes_nothing
    say("write the delivery page")
    write("#{open_intent_dir}/resources/tmp/page.html", "<p>page</p>\n")
    result = call("1", "resources/tmp/page.html", "--asked", "delivery page")

    assert_equal [1, []], [result.code, reported]
  end

  def open_intent_dir = retrieval.intent("1").dir

  def test_the_outcome_gets_one_line_under_a_reports_heading
    say("write the delivery page")
    call("1", REPORT, "--asked", "delivery page")

    assert_equal "#{OUTCOME}\n## Reports\n\n- #{REPORT}, asked: \"delivery page\"\n", outcome
  end

  def test_a_second_record_of_the_same_path_writes_nothing
    say("write the delivery page")
    call("1", REPORT, "--asked", "delivery page")
    result = call("1", REPORT, "--asked", "delivery page")

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
    say("write the delivery page")
    call("1", REPORT, "--asked", "delivery page")

    assert_includes store_database.rows("SELECT path FROM documents").map { |row| row["path"] }, REPORT
  end
end
