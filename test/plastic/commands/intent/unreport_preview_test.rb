# frozen_string_literal: true

require_relative "../../../test_helper"

# The dry run of plastic intent unreport, on homes of their own: the test's own home sits inside a transaction, which the
# disposable copy of a preview cannot read.
class IntentUnreportPreviewTest < Plastic::TestCase
  REPORT = "resources/output/reports/page.html"

  def seed_report(home)
    seed_intents(home, "Alpha")
    folder = Dir.glob(File.join(home, "stores", "global", "store", "1--*")).first
    FileUtils.mkdir_p(File.join(folder, File.dirname(REPORT)))
    File.write(File.join(folder, REPORT), "<p>page</p>\n")
    call_in(home, "intent", "report", "1", REPORT)
  end

  def test_the_dry_run_changes_nothing_and_answers_as_the_call_does
    twin = twin_run("intent", "unreport", "1", REPORT, "--reason", "recorded by mistake") { |home| seed_report(home) }

    assert_equal 0, twin.applied.code, twin.applied.err
    assert_preview_matches_apply(twin)
  end

  def test_the_dry_run_of_a_move_changes_nothing_and_answers_as_the_call_does
    twin = twin_run("intent", "unreport", "1", REPORT, "--reason", "recorded by mistake", "--to-tmp") { |home| seed_report(home) }

    assert_equal 0, twin.applied.code, twin.applied.err
    assert_preview_matches_apply(twin)
  end
end
