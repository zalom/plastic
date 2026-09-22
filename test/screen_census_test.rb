require "minitest/autorun"
require_relative "support/screen_census"

# Intent 331a, T3: resources/probes/census.rb scanned the owner's real
# ~/.claude/projects/*/*.jsonl transcripts, which is neither hermetic nor
# reproducible in the suite. ScreenCensus.count takes an explicit file list
# instead, proven here against a checked-in fixture transcript rather than
# live session history.
class ScreenCensusTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  FIXTURE = File.join(REPO, "test", "fixtures", "census_transcript.jsonl")

  def test_census_counts_reply_shapes_from_a_fixture_transcript
    rows = ScreenCensus.count([FIXTURE])

    assert_equal 2, rows["2026-09-01"]["total"]
    assert_equal 1, rows["2026-09-01"]["opens_reply"]
    assert_equal 1, rows["2026-09-01"]["prose_first"]
    assert_equal 0, rows["2026-09-01"]["fenced"]

    assert_equal 1, rows["2026-09-02"]["total"]
    assert_equal 0, rows["2026-09-02"]["opens_reply"]
    assert_equal 0, rows["2026-09-02"]["prose_first"]
    assert_equal 1, rows["2026-09-02"]["fenced"]
  end

  def test_census_ignores_non_assistant_lines_and_screenless_replies
    rows = ScreenCensus.count([FIXTURE])
    total = rows.values.sum { |r| r["total"] }
    # 5 lines in the fixture: one user line and one screenless assistant
    # reply must never be counted, leaving exactly 3.
    assert_equal 3, total
  end
end
