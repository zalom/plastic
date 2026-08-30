# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/backfill_intent"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/outcome_guard"

# BackfillIntent (intent 308): the four judgment documents are written from the record at
# intent end, only where a target is missing or still the placeholder. Drives the lib in
# process with a fake git runner; hermetic tmp home, no eval, no ENV seam, no real
# ~/.plastic read (templates are passed explicitly).
class BackfillIntentTest < Minitest::Test
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL
  TEMPLATES = File.expand_path("../templates", __dir__)

  class FakeRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def initialize(diffstat_status: 0, diffstat_stdout: "2 files changed, 9 insertions(+)\n", raise_on_diff: false)
      @diffstat_status = diffstat_status
      @diffstat_stdout = diffstat_stdout
      @raise_on_diff = raise_on_diff
    end

    def run(*args)
      case args[2]
      when "rev-parse"
        args.include?("--show-toplevel") ? Result.new(0, "/fake/repo\n", "") : Result.new(args.include?("main") ? 0 : 1, "", "")
      when "symbolic-ref" then Result.new(1, "", "")
      when "diff"
        raise IOError, "git exploded" if @raise_on_diff

        Result.new(@diffstat_status, @diffstat_stdout, "boom")
      else Result.new(1, "", "unhandled #{args.inspect}")
      end
    end
  end

  DECISIONS = "- D1. First ruling.\n- D2. Second ruling that wraps\n  onto a continuation line.\n"
  CHECKLIST = <<~MD
    # Checklist: Demo backfill intent

    ## In Progress
    - [ ] Step 3 - write the docs
      with a wrapped continuation

    ## Completed
    - [x] Step 1 - tests first; red commit abc123
    - [X] Step 2 - code; green commit def456

    ## Session Log
    | Date | Items Completed | Notes |
    |------|-----------------|-------|
    | 2026-08-30 | 1, 2 | on the branch |
  MD

  def setup
    @home = Dir.mktmpdir("backfill-intent-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @now = Time.utc(2026, 8, 30, 2, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def build_intent(id: "308z", with_decisions: true, sentinel_docs: true, checklist: CHECKLIST, insights: true)
    dir = File.join(@store, "#{id}--demo")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "actions", ".gitkeep"), "")
    context = with_decisions ? "Some context.\n\n### Decisions\n#{DECISIONS}" : "Some context, no decisions.\n"
    insight_lines = insights ? "2026-08-30T01:00:00Z · How · orchestrator — first insight\n" : ""
    File.write(File.join(dir, "#{id}--demo.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "Demo backfill intent"
      sources: []
      chain: []
      created: 2026-08-29
      author: human
      tags: []
      ---

      ## Intent
      Backfill the four documents from the record.
      Second line of the ask.

      ## Context
      #{context}
      ## Outcome
      (placeholder)

      ## Insights
      #{insight_lines}
      ## Links
      <!-- none -->
    MD
    File.write(File.join(dir, "checklist.md"), checklist) if checklist
    if sentinel_docs
      %w[spec.md plan.md outcome.md].each { |f| File.write(File.join(dir, f), "#{SENTINEL}\n# stub\n") }
    end
    dir
  end

  def run_backfill(dir, disposition: "delivered", summary: "Shipped the thing.", runner: FakeRunner.new)
    BackfillIntent.run(intent_dir: dir, store: @store, id: File.basename(dir).split("--").first,
                       disposition: disposition, summary: summary, home: @home, runner: runner,
                       templates_dir: TEMPLATES, now: @now)
  end

  def read(dir, rel) = File.read(File.join(dir, rel))

  # --- target selection --------------------------------------------------------------

  def test_sentinel_docs_and_gitkeep_only_actions_are_all_backfilled
    dir = build_intent
    result = run_backfill(dir)

    assert_equal BackfillIntent::TARGETS, result[:written]
    assert_empty result[:skipped]
    BackfillIntent::TARGETS.each do |rel|
      content = read(dir, rel)
      refute_includes content, SENTINEL, "#{rel} must not carry the sentinel"
      title_idx = content.lines.index { |l| l.start_with?("# ") }
      assert_match(/\A<!-- backfilled from the record by end-intent on 2026-08-30T02:00:00Z -->$/,
                   content.lines[title_idx + 1], "#{rel} marker must follow the title line")
      assert Savepoint.stage_file_present?(File.join(dir, rel)), "#{rel} must read as real"
    end
    assert Savepoint.has_real_action?(dir)
  end

  def test_real_documents_are_never_touched
    dir = build_intent(sentinel_docs: false)
    real = { "spec.md" => "# Spec: mine\n\n## Problem\nhand written\n",
             "plan.md" => "# Plan: mine\n", "outcome.md" => "---\ndisposition: delivered\n---\n# Outcome: mine\n\n## Summary\nmine\n",
             "actions/ACTION_2.md" => "# ACTION_2: mine\n" }
    real.each { |rel, body| File.write(File.join(dir, rel), body) }

    result = run_backfill(dir)

    assert_empty result[:written]
    assert_equal BackfillIntent::TARGETS, result[:skipped]
    real.each { |rel, body| assert_equal body, read(dir, rel), "#{rel} must be byte-identical" }
    refute File.exist?(File.join(dir, "actions", "ACTION_1.md"))
  end

  def test_only_the_placeholder_targets_are_written_when_some_are_real
    dir = build_intent
    File.write(File.join(dir, "spec.md"), "# Spec: mine\n")
    File.write(File.join(dir, "actions", "ACTION_1.md"), "# ACTION_1: mine\n")

    result = run_backfill(dir)

    assert_equal %w[plan.md outcome.md], result[:written]
    assert_equal %w[spec.md actions/ACTION_1.md], result[:skipped]
    assert_equal "# Spec: mine\n", read(dir, "spec.md")
    assert_equal "# ACTION_1: mine\n", read(dir, "actions/ACTION_1.md")
  end

  def test_missing_files_count_as_targets
    dir = build_intent(sentinel_docs: false)
    FileUtils.rm_rf(File.join(dir, "actions"))

    result = run_backfill(dir)

    assert_equal BackfillIntent::TARGETS, result[:written]
    assert File.exist?(File.join(dir, "actions", "ACTION_1.md"))
  end

  # --- content ------------------------------------------------------------------------

  def test_spec_copies_problem_and_decisions_verbatim_and_keeps_stubs
    dir = build_intent
    run_backfill(dir)
    spec = read(dir, "spec.md")

    assert_includes spec, "## Problem\nBackfill the four documents from the record.\nSecond line of the ask.\n"
    assert_includes spec, "## Decisions\n#{DECISIONS}"
    assert_includes spec, "## Approach\n(the chosen approach, in prose)\n"
    assert_includes spec, "## Alternatives Considered\n- <alternative>: not chosen because ...\n"
    assert_includes spec, "## Open Questions\nNone\n"
    ac = spec[/## Acceptance Criteria\n(.*?)\n## Open Questions/m, 1]
    assert_equal "- [ ] Step 3 - write the docs\n  with a wrapped continuation\n- [x] Step 1 - tests first; red commit abc123\n- [X] Step 2 - code; green commit def456\n", ac
    assert_equal "# Spec: Demo backfill intent\n", spec.lines.first
  end

  def test_spec_without_decisions_says_so_instead_of_failing
    dir = build_intent(with_decisions: false)
    result = run_backfill(dir)

    assert_includes result[:written], "spec.md"
    assert_includes read(dir, "spec.md"), "## Decisions\n(none recorded in the intent file)\n"
    assert(result[:notes].any? { |n| n.include?("### Decisions") })
  end

  def test_plan_lists_the_items_and_the_insights
    dir = build_intent
    run_backfill(dir)
    plan = read(dir, "plan.md")

    assert_includes plan, "## Goal\nDemo backfill intent\n"
    assert_includes plan, "## Steps\n- [ ] Step 3 - write the docs\n  with a wrapped continuation\n- [x] Step 1"
    assert_includes plan, "## Notes\n2026-08-30T01:00:00Z · How · orchestrator — first insight\n"
  end

  def test_plan_without_insights_or_checklist_uses_the_empty_markers
    dir = build_intent(insights: false, checklist: nil)
    run_backfill(dir)
    plan = read(dir, "plan.md")

    assert_includes plan, "## Steps\n(no checklist items recorded)\n"
    assert_includes plan, "## Notes\n(no insights recorded)\n"
    assert(run_backfill(build_intent(id: "308t", insights: false, checklist: nil))[:notes].any? { |n| n.include?("checklist.md is missing") })
  end

  def test_action_renders_every_item_and_the_session_log_table
    dir = build_intent
    run_backfill(dir)
    action = read(dir, "actions/ACTION_1.md")

    assert_equal "# ACTION_1: Demo backfill intent\n", action.lines.first
    assert_includes action, "## Items\n- [ ] Step 3"
    assert_includes action, "- [X] Step 2 - code; green commit def456\n"
    assert_includes action, "## Session Log\n| Date | Items Completed | Notes |\n|------|-----------------|-------|\n| 2026-08-30 | 1, 2 | on the branch |\n"
  end

  def test_outcome_carries_the_disposition_summary_delivered_verification_and_follow_ups
    dir = build_intent
    run_backfill(dir, disposition: "abandoned", summary: "  Stopped early.  ")
    outcome = read(dir, "outcome.md")

    assert_nil OutcomeGuard.reason(dir, "abandoned")
    assert_equal "---\ndisposition: abandoned\n---\n# Outcome: Demo backfill intent\n", outcome.lines.first(4).join
    assert_includes outcome, "## Summary\nStopped early.\n"
    assert_includes outcome, "## Delivered\n- [x] Step 1 - tests first; red commit abc123\n- [X] Step 2 - code; green commit def456\n"
    assert_includes outcome, "## Verification\nDiffstat unavailable: this intent provisioned no code worktree\n"
    assert_includes outcome, "## Follow-ups\n- [ ] Step 3 - write the docs\n  with a wrapped continuation\n"
    summary_line = outcome.lines.drop_while { |l| l.strip != "## Summary" }.drop(1).find { |l| !l.strip.empty? && !l.start_with?("#", "<!--") }
    assert_equal "Stopped early.\n", summary_line
  end

  def test_outcome_without_summary_or_open_items_uses_the_empty_markers
    dir = build_intent(checklist: CHECKLIST.sub("- [ ] Step 3 - write the docs\n  with a wrapped continuation\n", ""))
    run_backfill(dir, summary: nil)
    outcome = read(dir, "outcome.md")

    assert_includes outcome, "## Summary\n(no summary given at close)\n"
    assert_includes outcome, "## Follow-ups\nNone\n"
  end

  # A project-store intent whose code worktree exists on disk: <home>/.plastic/projects/
  # demo/store, projects.yml naming the repo, and <repo>/.claude/worktrees/<id>--demo.
  def build_project_intent(id: "308w", worktree: true)
    plastic_home = File.join(@home, ".plastic")
    store = File.join(plastic_home, "projects", "demo", "store")
    repo = File.join(@home, "repo")
    FileUtils.mkdir_p(store)
    FileUtils.mkdir_p(File.join(repo, ".claude", "worktrees", "#{id}--demo")) if worktree
    File.write(File.join(plastic_home, "projects.yml"), "projects:\n  demo:\n    path: #{repo}\n")
    dir = File.join(store, "#{id}--demo")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "#{id}--demo.md"), "---\nid: \"#{id}\"\nintent: \"Worktree intent\"\n---\n\n## Intent\nx\n")
    File.write(File.join(dir, "checklist.md"), CHECKLIST)
    %w[spec.md plan.md outcome.md].each { |f| File.write(File.join(dir, f), "#{SENTINEL}\n") }
    [dir, store]
  end

  def test_diffstat_comes_from_the_intents_own_worktree_only
    dir, store = build_project_intent
    BackfillIntent.run(intent_dir: dir, store: store, id: "308w", disposition: "delivered", summary: "s",
                       home: @home, runner: FakeRunner.new, templates_dir: TEMPLATES, now: @now)
    assert_includes read(dir, "outcome.md"),
                    "## Verification\nDiffstat against main:\n```\n2 files changed, 9 insertions(+)\n```\n"

    dir2, = build_project_intent(id: "308v", worktree: false)
    BackfillIntent.run(intent_dir: dir2, store: store, id: "308v", disposition: "delivered", summary: "s",
                       home: @home, runner: FakeRunner.new, templates_dir: TEMPLATES, now: @now)
    assert_includes read(dir2, "outcome.md"), "Diffstat unavailable: this intent provisioned no code worktree\n"
  end

  def test_failing_diffstat_and_raising_git_both_yield_an_unavailable_line
    dir, store = build_project_intent
    BackfillIntent.run(intent_dir: dir, store: store, id: "308w", disposition: "delivered", summary: "s",
                       home: @home, runner: FakeRunner.new(diffstat_status: 1), templates_dir: TEMPLATES, now: @now)
    assert_includes read(dir, "outcome.md"), "## Verification\nDiffstat unavailable: boom\n"

    dir2, = build_project_intent(id: "308u")
    result = BackfillIntent.run(intent_dir: dir2, store: store, id: "308u", disposition: "delivered", summary: "s",
                                home: @home, runner: FakeRunner.new(raise_on_diff: true), templates_dir: TEMPLATES, now: @now)
    assert_includes result[:written], "outcome.md"
    assert_includes read(dir2, "outcome.md"), "Diffstat unavailable: git exploded\n"
  end

  def test_missing_intent_file_writes_nothing_and_notes_it
    dir = build_intent
    File.delete(File.join(dir, "308z--demo.md"))
    result = run_backfill(dir)

    assert_empty result[:written]
    assert(result[:notes].any? { |n| n.include?("intent file is missing") })
    assert_equal "#{SENTINEL}\n# stub\n", read(dir, "spec.md")
  end

  def test_write_leaves_no_temp_file_and_is_idempotent
    dir = build_intent
    first = run_backfill(dir)
    assert_empty Dir.glob(File.join(dir, "**", ".filing-*"))
    before = BackfillIntent::TARGETS.map { |rel| read(dir, rel) }

    second = run_backfill(dir)
    assert_empty second[:written]
    assert_equal BackfillIntent::TARGETS, first[:written]
    assert_equal before, BackfillIntent::TARGETS.map { |rel| read(dir, rel) }
  end

  def test_checklist_reader_keeps_items_verbatim_and_skips_tables
    items = BackfillIntent.checklist_items(CHECKLIST)
    assert_equal 3, items.size
    assert_equal [false, true, true], items.map { |i| i[:done] }
    assert_equal ["## In Progress", "## Completed", "## Completed"], items.map { |i| i[:section] }
    assert_equal "- [ ] Step 3 - write the docs\n  with a wrapped continuation", items.first[:line]
  end

  def test_missing_templates_dir_falls_back_to_the_built_in_stubs
    dir = build_intent
    BackfillIntent.run(intent_dir: dir, store: @store, id: "308z", disposition: "delivered", summary: "s",
                       home: File.join(@home, "nowhere"), runner: FakeRunner.new,
                       templates_dir: File.join(@home, "missing-templates"), now: @now)
    assert_includes read(dir, "spec.md"), "## Goals\n- ...\n"
  end
  # --- review folds (intent 308 plan review) ---------------------------------------------

  def test_a_sentinel_over_hand_written_content_is_left_untouched_and_noted
    dir = build_intent
    edited = "#{SENTINEL}\n# Spec: Demo backfill intent\n\n## Problem\nI wrote this by hand.\n"
    File.write(File.join(dir, "spec.md"), edited)
    template_only = "#{SENTINEL}\n#{File.read(File.join(TEMPLATES, 'plan.md')).sub('{{INTENT_NAME}}', 'Demo backfill intent')}"
    File.write(File.join(dir, "plan.md"), template_only)

    result = run_backfill(dir)

    assert_equal edited, read(dir, "spec.md"), "an edited sentinel file is real content"
    assert_includes result[:skipped], "spec.md"
    assert(result[:notes].any? { |n| n.include?("spec.md carries a sentinel over hand-written content") })
    assert_includes result[:written], "plan.md", "a sentinel over the untouched template is a placeholder"
    refute_includes read(dir, "plan.md"), SENTINEL
  end

  def test_a_sentinel_action_file_with_a_body_is_left_untouched
    dir = build_intent
    File.write(File.join(dir, "actions", "ACTION_1.md"), "#{SENTINEL}\n# ACTION_1\n\n1. do the thing\n")
    result = run_backfill(dir)

    refute_includes result[:written], "actions/ACTION_1.md"
    assert_includes read(dir, "actions/ACTION_1.md"), "1. do the thing"
  end

  def test_blank_intent_name_falls_back_to_the_directory_name
    dir = build_intent
    File.write(File.join(dir, "308z--demo.md"), "## Intent\nno frontmatter at all\n")
    result = run_backfill(dir)

    assert_equal "# Spec: 308z--demo\n", read(dir, "spec.md").lines.first
    assert(result[:notes].any? { |n| n.include?("no frontmatter intent name") })
  end

  def test_stale_filing_files_are_removed_before_writing
    dir = build_intent
    File.write(File.join(dir, ".filing-spec.md"), "half")
    File.write(File.join(dir, "actions", ".filing-ACTION_1.md"), "half")
    run_backfill(dir)

    assert_empty Dir.glob(File.join(dir, "**", ".filing-*"))
  end

  def test_one_savepoint_line_records_the_backfill_and_stays_idempotent
    dir = build_intent
    run_backfill(dir)
    lines = File.read(File.join(dir, "savepoint.md")).lines.map(&:strip)
    assert_equal ["2026-08-30T02:00:00Z  Exec  backfilled spec.md, plan.md, actions/ACTION_1.md, outcome.md"], lines
    assert_empty Savepoint.savepoint_phantom_lines(dir), "the backfill line must never read as a phantom"

    run_backfill(dir)
    assert_equal 1, File.read(File.join(dir, "savepoint.md")).lines.size

    dir2 = build_intent(id: "308s")
    File.write(File.join(dir2, "spec.md"), "# Spec: mine\n")
    run_backfill(dir2)
    assert_match(/Exec  backfilled plan\.md, actions\/ACTION_1\.md, outcome\.md$/, File.read(File.join(dir2, "savepoint.md")))
  end

  def test_backfilled_outcome_parses_as_frontmatter_for_the_guard
    dir = build_intent
    run_backfill(dir, disposition: "delivered")
    assert_nil OutcomeGuard.reason(dir, "delivered")
    assert_match(/outcome\.md frontmatter disposition is "delivered"/, OutcomeGuard.reason(dir, "abandoned"))
  end
end
