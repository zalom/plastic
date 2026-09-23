require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

# Acceptance findings N3 and N18: `end-intent --dry-run` must refuse exactly
# what the real close refuses, and a delivered close of a scaffold nobody
# touched is refused (exit 8) before anything is written. A legacy intent
# whose lifecycle files are simply missing still closes through the backfill,
# as it did before.
class EndIntentDryRunAgreementTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/end-intent", __dir__)
  NEW_INTENT = File.expand_path("../scripts/new-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  SESSION = "agreement-session".freeze

  def setup
    @root = Dir.mktmpdir("end-agreement")
    @store = File.join(@root, ".plastic", "stores", "demo", "store")
    @index = File.join(@root, "INDEX.md")
    FileUtils.mkdir_p([@store, File.join(@root, "tmp")])
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def end_intent(*args, disposition: "delivered")
    env = {"CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => File.join(@root, "tmp"), "HOME" => @root, "RUBYOPT" => nil, "BUNDLER_SETUP" => nil}
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, "--store", @store, "--id", "1", "--disposition", disposition,
      "--index", @index, "--no-commit", "--session", SESSION, *args],
      err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def scaffold
    env = {"HOME" => @root, "RUBYOPT" => nil, "BUNDLER_SETUP" => nil}
    IO.popen(env, [RbConfig.ruby, NEW_INTENT, "--store", @store, "--intent", "demo work", "--slug", "demo",
      "--templates", TEMPLATES], err: [:child, :out], &:read)
    dir = File.join(@store, "1--demo")
    File.write(@index, "# INDEX\n\n## Active\n- [1 - demo work](store/1--demo/1--demo.md)\n\n## Completed\n\n## Abandoned\n")
    dir
  end

  def snapshot(dir)
    Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }.sort.to_h { |f| [f, File.read(f)] }
      .merge(@index => File.read(@index))
  end

  def test_untouched_scaffold_delivered_close_is_refused_with_exit_8_and_nothing_written
    dir = scaffold
    before = snapshot(dir)

    out, status = end_intent("--outcome-summary", "unworked")

    assert_equal 8, status, out
    assert_includes out, "refusing to deliver an untouched scaffold"
    assert_equal before, snapshot(dir)
  end

  def test_untouched_scaffold_dry_run_refuses_the_same_way
    dir = scaffold
    before = snapshot(dir)

    out, status = end_intent("--dry-run")

    assert_equal 8, status, out
    assert_includes out, "refusing to deliver an untouched scaffold"
    assert_equal before, snapshot(dir)
  end

  def test_untouched_scaffold_can_still_be_abandoned
    dir = scaffold

    out, status = end_intent("--outcome-summary", "dropped", disposition: "abandoned")

    assert_equal 0, status, out
    assert_includes File.read(@index), "## Abandoned\n- [1"
    assert_includes File.read(File.join(dir, "savepoint.md")), "Done  abandoned"
  end

  def test_a_ticked_checklist_is_worked_and_closes_through_the_backfill
    dir = scaffold
    File.write(File.join(dir, "checklist.md"), "# Checklist: demo\n\n- [x] S1 the change\n")

    out, status = end_intent("--outcome-summary", "shipped")

    assert_equal 0, status, out
    assert_includes File.read(File.join(dir, "outcome.md")), "backfilled from the record"
  end

  def test_a_savepoint_past_what_is_worked
    dir = scaffold
    File.open(File.join(dir, "savepoint.md"), "a") { |f| f.puts "2026-09-23T01:00:00Z  Report  did the work" }

    _out, status = end_intent("--dry-run")

    assert_equal 0, status
  end

  def test_legacy_intent_with_missing_lifecycle_files_still_delivers
    dir = scaffold
    %w[spec.md plan.md checklist.md outcome.md savepoint.md].each { |f| File.delete(File.join(dir, f)) }

    out, status = end_intent("--outcome-summary", "legacy close")

    assert_equal 0, status, out
    assert_includes File.read(@index), "## Completed\n- [1"
  end

  def test_dry_run_predicts_the_hollow_report_refusal
    dir = scaffold
    File.write(File.join(dir, "actions", "ACTION_1.md"), "# ACTION_1\n\n### S1 - the thing\n")
    File.write(File.join(dir, "outcome.md"), <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome: demo

      ## Delivered
      - D1 something shipped

      ## Needs you
      None
    MD

    dry_out, dry_status = end_intent("--dry-run")
    real_out, real_status = end_intent

    assert_equal 7, real_status, real_out
    assert_equal real_status, dry_status, dry_out
    assert_includes dry_out, "would refuse a hollow delivered close"
  end

  def test_dry_run_passes_when_the_real_close_passes
    dir = scaffold
    File.write(File.join(dir, "checklist.md"), "# Checklist: demo\n\n- [x] S1 the change\n")

    dry_out, dry_status = end_intent("--dry-run")

    assert_equal 0, dry_status, dry_out
    assert_includes dry_out, "would backfill: spec.md, plan.md, actions/ACTION_1.md, outcome.md"
    assert_equal 0, end_intent.last
  end

  def dirty_code_worktree
    repo = File.join(@root, "repo")
    code = File.join(repo, ".claude", "worktrees", "1--demo")
    FileUtils.mkdir_p(code)
    system("git", "init", "-q", code)
    File.write(File.join(code, "loose.txt"), "uncommitted\n")
    File.write(File.join(@root, ".plastic", "projects.yml"), "projects:\n  demo:\n    path: #{repo}\n")
  end

  def test_dry_run_predicts_a_dirty_worktree_refusal
    dir = scaffold
    File.write(File.join(dir, "checklist.md"), "# Checklist: demo\n\n- [x] S1 the change\n")
    dirty_code_worktree

    dry_out, dry_status = end_intent("--dry-run")
    real_out, real_status = end_intent

    assert_equal 5, real_status, real_out
    assert_equal 5, dry_status, dry_out
    assert_includes dry_out, "would refuse at disarm"
  end

  def test_changes_in_the_code_worktree_count_as_work
    scaffold
    dirty_code_worktree

    out, status = end_intent("--dry-run")

    assert_equal 5, status, out
    refute_includes out, "untouched scaffold"
  end
end
