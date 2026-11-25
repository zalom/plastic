# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentUnreportClosedTest < Plastic::TestCase
  REPORT = "resources/output/reports/page.html"
  OUTCOME = "# Outcome\n\nDelivered.\n"

  def call(*args) = plastic("intent", *args, table: Plastic::CLI::TABLE)

  def unreport = call("unreport", "1", REPORT, "--reason", "recorded by mistake")

  def dir = retrieval.intent("1").dir

  def amended = store_database.rows("SELECT path, sha256, old_text, new_text FROM work_log WHERE kind = 'amended'").map(&:values)

  def close(status) = store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = '#{status}' WHERE intent_id = '1'") }

  def setup
    super
    open_intent
    write("#{dir}/outcome.md", OUTCOME)
    write("#{dir}/#{REPORT}", "<p>page</p>\n")
    sync_up
    call("report", "1", REPORT)
  end

  def test_a_closed_intent_gets_an_amended_line_with_the_sha256_of_the_new_outcome
    close("done")
    result = unreport

    assert_equal [0, [["outcome.md", Digest::SHA256.hexdigest(OUTCOME), "- #{REPORT}", ""]]], [result.code, amended]
  end

  def test_an_abandoned_intent_gets_an_amended_line_too
    close("abandoned")
    unreport

    assert_equal 1, amended.size
  end

  def test_an_open_intent_gets_no_amended_line
    unreport

    assert_empty amended
  end

  def test_a_sync_up_after_the_removal_reads_the_closed_outcome
    close("done")
    unreport
    result = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

    assert_equal [0, OUTCOME], [result.code, retrieval.fetch("1", "outcome.md").body]
  end
end
