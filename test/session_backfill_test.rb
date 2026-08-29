# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/session_backfill"

# Intent 301: the backfill renderer is a pure function of a day directory's
# ledger files. In-process only; no spawning, no PLASTIC_TMP needed.
class SessionBackfillTest < Minitest::Test
  DAY = "20260829"

  def setup
    @store = Dir.mktmpdir("backfill")
    @dir = SessionLedger.day_dir(@store, DAY)
    FileUtils.mkdir_p(@dir)
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def line(state, summary, session: "abc", project: "plastic")
    SessionLedger.checklist_line(state, session, project, summary)
  end

  def seed_checklist(*lines)
    File.write(SessionLedger.checklist_path(@store, DAY), SessionLedger.checklist_header(DAY) + lines.join)
  end

  def seed_savepoint(*lines)
    File.write(SessionLedger.savepoint_path(@store, DAY), lines.join)
  end

  def render
    SessionBackfill.render(@dir, day: DAY)
  end

  def test_render_returns_the_four_documents_with_no_sentinel
    seed_checklist(line(:done, "fix typo"), line(:open, "add test"), line(:pending, "hello"))
    seed_savepoint(SessionLedger.savepoint_line("Item", "abc", "plastic", "fix typo", now: Time.utc(2026, 8, 29, 10)))
    docs = render
    assert_equal %w[actions/ACTION_1.md outcome.md plan.md spec.md], docs.keys.sort
    docs.each_value { |body| refute_includes body, "plastic:placeholder" }
  end

  def test_spec_lists_every_line_except_dropped_with_tags
    seed_checklist(line(:done, "fix typo"), line(:dropped, "noise"), line(:open, "add test", session: "zzz"))
    spec = render["spec.md"]
    assert_includes spec, "## Requests"
    assert_includes spec, "[abc] [plastic] fix typo"
    assert_includes spec, "[zzz] [plastic] add test"
    refute_includes spec, "noise"
  end

  def test_plan_lists_savepoint_lines_in_order_and_passes_unparsed_lines_through
    good = SessionLedger.savepoint_line("Item", "abc", "plastic", "first", now: Time.utc(2026, 8, 29, 10))
    doubled = "2026-08-29T10:01:00Z  Note  [abc] [plastic] two  spaces inside\n"
    truncated = "2026-08-29T10:02:00Z  Done"
    seed_savepoint(good, doubled, truncated)
    plan = render["plan.md"]
    assert_includes plan, "## Steps"
    first = plan.index("first")
    second = plan.index("two  spaces inside")
    third = plan.index("2026-08-29T10:02:00Z  Done")
    assert first && second && third && first < second && second < third
  end

  def test_outcome_is_delivered_with_done_carried_and_promoted_sections
    seed_checklist(line(:done, "shipped"), line(:moved, "tomorrow"), line(:promoted, "became intent"), line(:open, "still open"))
    outcome = render["outcome.md"]
    assert outcome.start_with?("---\ndisposition: delivered\n---\n")
    delivered = outcome[/## Delivered\n(.*?)\n## /m, 1]
    carried = outcome[/## Carried\n(.*?)\n## /m, 1]
    promoted = outcome[/## Promoted\n(.*?)\z/m, 1]
    assert_includes delivered, "shipped"
    assert_includes carried, "tomorrow"
    refute_includes carried, "became intent"
    assert_includes promoted, "became intent"
  end

  def test_outcome_is_abandoned_with_empty_sections_when_there_is_no_checklist
    docs = render
    assert docs["outcome.md"].start_with?("---\ndisposition: abandoned\n---\n")
    assert_includes docs["spec.md"], "## Requests"
    assert_includes docs["plan.md"], "## Steps"
    assert_includes docs["actions/ACTION_1.md"], "# ACTION_1"
  end

  def test_malformed_checklist_line_is_skipped_without_raising
    seed_checklist(line(:done, "good"), "garbage line\n", line(:open, "also good"))
    docs = render
    assert_includes docs["spec.md"], "good"
    assert_includes docs["spec.md"], "also good"
    refute_includes docs["spec.md"], "garbage"
  end

  def test_action_lists_items_one_per_line_without_grouping
    seed_checklist(line(:done, "a", project: "x"), line(:open, "b", project: "y"))
    action = render["actions/ACTION_1.md"]
    assert_includes action, "- [x] [abc] [x] a"
    assert_includes action, "- [ ] [abc] [y] b"
    refute_includes action, "## x"
  end

  def test_parse_savepoint_line_anchors_on_the_timestamp
    parsed = SessionBackfill.parse_savepoint_line("2026-08-29T10:00:00Z  Item  [abc] [plastic] hello  world\n")
    assert_equal "Item", parsed[:event]
    assert_equal "[abc] [plastic] hello  world", parsed[:rest]
    assert_nil SessionBackfill.parse_savepoint_line("no timestamp here\n")
  end
end
