# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/scaffold_intent"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/spec_header"
require_relative "../scripts/lib/outcome_guard"

# scaffold-intent (intent 213): drives the LIB in process for the logic assertions (a
# fake git runner stands in for ACTION_3's shared repo/base-branch helpers), and the real
# SCRIPT as a subprocess (test/end_intent_test.rb:44-49's IO.popen pattern) for the
# exit-code contract. Hermetic: every fixture lives under Dir.mktmpdir, no eval, no
# network, no ambient session id, no real ~/.plastic read.
class ScaffoldIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/scaffold-intent", __dir__)
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL

  # Fake git runner (Worktree::ShellRunner's `run(*args) -> Result` contract): drives
  # resolve_repo_dir / detect_base_branch / diffstat without ever touching real git.
  class FakeRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def initialize(repo: "/fake/repo", base_branch: "main",
                   diffstat_status: 0, diffstat_stdout: "1 file changed, 2 insertions(+)\n",
                   diffstat_stderr: "")
      @repo = repo
      @base_branch = base_branch
      @diffstat_status = diffstat_status
      @diffstat_stdout = diffstat_stdout
      @diffstat_stderr = diffstat_stderr
    end

    def run(*args)
      case args[2]
      when "rev-parse"
        if args.include?("--show-toplevel")
          Result.new(0, "#{@repo}\n", "")
        elsif args.include?(@base_branch)
          Result.new(0, "", "")
        else
          Result.new(1, "", "not found")
        end
      when "symbolic-ref"
        Result.new(1, "", "no upstream configured")
      when "diff"
        Result.new(@diffstat_status, @diffstat_stdout, @diffstat_stderr)
      else
        Result.new(1, "", "unhandled fake git call: #{args.inspect}")
      end
    end
  end

  def setup
    @home = Dir.mktmpdir("scaffold-intent-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @tmp_bridge = Dir.mktmpdir("scaffold-intent-bridge")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp_bridge)
  end

  # --- fixtures ----------------------------------------------------------------

  DECISIONS_BODY = <<~MD.freeze
    - First decision, plain.
    - Second decision that wraps across
      a continuation line for wrapped-line testing.
    - Third decision with a `backtick` and, a comma.
  MD

  ACCEPTANCE_CRITERIA_BODY = <<~MD.freeze
    ### Group A
    - [ ] First criterion that wraps across
      a continuation line.
    - [ ] Second criterion, with a comma and `backtick`.
  MD

  def build_intent(id: "213z", slug: "demo", with_decisions: true)
    intent_dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(intent_dir)

    context_body = if with_decisions
                      "Some context prose.\n\n### Decisions\n#{DECISIONS_BODY}"
                    else
                      "Some context prose, no decisions recorded yet.\n"
                    end

    File.write(File.join(intent_dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "Demo scaffold intent"
      sources: []
      chain: []
      created: 2026-07-01
      author: human
      tags: []
      ---

      ## Intent
      Demo intent for scaffold-intent tests.

      ## Context
      #{context_body}

      ## Outcome
      (placeholder)

      ## Insights
      (placeholder)

      ## Links
      (placeholder)
    MD
    intent_dir
  end

  def write_spec(intent_dir, sentinel: false, with_ac: true)
    path = File.join(intent_dir, "spec.md")
    if sentinel
      File.write(path, "#{SENTINEL}\n")
      return path
    end

    ac_block = with_ac ? "## Acceptance Criteria\n#{ACCEPTANCE_CRITERIA_BODY}\n" : ""
    File.write(path, <<~MD)
      # Spec: Demo scaffold intent

      ## Problem
      stub

      #{ac_block}## Open Questions
      None
    MD
    path
  end

  def run_scaffold(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  # --- 1: spec copies ### Decisions byte for byte -------------------------------

  def test_spec_copies_decisions_byte_for_byte
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    assert_equal :ok, result[:status]
    assert_includes File.read(result[:path]), DECISIONS_BODY.rstrip
  end

  # --- 2: spec writes all 8 section headings, template order --------------------

  def test_spec_writes_all_eight_section_headings_in_order
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    headings = File.read(result[:path]).lines.map(&:rstrip).select { |l| l.start_with?("## ") }
    assert_equal ScaffoldIntent::SPEC_SECTIONS, headings
  end

  # --- 3: Tier/Settled header lines, scaffolded spec is not settled -------------

  def test_spec_header_lines_and_not_settled
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    lines = File.read(result[:path]).lines
    assert_equal "Tier: S|M|L\n", lines[0]
    assert_match(/\A<!-- Settled: yes /, lines[1])
    assert_equal false, SpecHeader.parse_file(result[:path])[:settled]
  end

  # --- 4: other sections keep the template's stub text ---------------------------

  def test_spec_leaves_other_sections_as_template_stubs
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    written = File.read(result[:path])
    assert_includes written, "(the problem, stated as a problem, not a solution)"
    assert_includes written, "## Goals\n- ...\n"
    assert_includes written, "## Non-Goals\n- ...\n"
    assert_includes written, "(the chosen approach, in prose)"
    assert_includes written, "not chosen because"
    assert_includes written, "## Acceptance Criteria\n- [ ] ...\n"
  end

  # --- 5: spec exits 3 with no ### Decisions heading ------------------------------

  def test_spec_errors_when_no_decisions_heading
    intent_dir = build_intent(with_decisions: false)
    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    assert_equal 3, result[:code]
    refute File.exist?(File.join(intent_dir, "spec.md"))
  end

  # --- 6: checklist copies Acceptance Criteria byte for byte ---------------------

  def test_checklist_copies_acceptance_criteria_byte_for_byte
    intent_dir = build_intent
    write_spec(intent_dir)
    result = ScaffoldIntent.scaffold_checklist(intent_dir: intent_dir, force: false)
    assert_equal :ok, result[:status]
    written = File.read(result[:path])
    assert_includes written, ACCEPTANCE_CRITERIA_BODY.rstrip
  end

  # --- 7: checklist exits 3 on a sentinel spec, and on a missing AC heading ------

  def test_checklist_errors_on_sentinel_spec
    intent_dir = build_intent
    write_spec(intent_dir, sentinel: true)
    result = ScaffoldIntent.scaffold_checklist(intent_dir: intent_dir, force: false)
    assert_equal 3, result[:code]
    refute File.exist?(File.join(intent_dir, "checklist.md"))
  end

  def test_checklist_errors_on_missing_acceptance_criteria_heading
    intent_dir = build_intent
    write_spec(intent_dir, with_ac: false)
    result = ScaffoldIntent.scaffold_checklist(intent_dir: intent_dir, force: false)
    assert_equal 3, result[:code]
    refute File.exist?(File.join(intent_dir, "checklist.md"))
  end

  # --- 8: outcome writes the diffstat from the injected fake runner --------------

  def test_outcome_writes_diffstat_from_fake_runner
    intent_dir = build_intent
    runner = FakeRunner.new(diffstat_stdout: "3 files changed, 40 insertions(+)\n")
    result = ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: false, store: @store,
                                             id: "213z", runner: runner, home: @home)
    assert_equal :ok, result[:status]
    written = File.read(result[:path])
    assert_includes written, "Diffstat against main:"
    assert_includes written, "3 files changed, 40 insertions(+)"
  end

  # --- 9: --test-summary adds a second block; without it, none appears -----------

  def test_outcome_with_test_summary_appends_second_block
    intent_dir = build_intent
    ts = File.join(@home, "summary.txt")
    File.write(ts, "1955 runs, 9026 assertions, 0 failures, 0 errors, 0 skips\n")
    result = ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: false, store: @store,
                                             id: "213z", runner: FakeRunner.new, home: @home,
                                             test_summary: ts)
    written = File.read(result[:path])
    assert_includes written, "Test summary from #{ts}:"
    assert_includes written, "1955 runs, 9026 assertions, 0 failures, 0 errors, 0 skips"
  end

  def test_outcome_without_test_summary_has_no_second_block
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: false, store: @store,
                                             id: "213z", runner: FakeRunner.new, home: @home)
    refute_includes File.read(result[:path]), "Test summary from"
  end

  # --- 10: the scaffolder never decides disposition --------------------------------

  def test_outcome_does_not_decide_disposition
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: false, store: @store,
                                             id: "213z", runner: FakeRunner.new, home: @home)
    written = File.read(result[:path])
    assert_includes written, "disposition: delivered|abandoned"

    refusal = OutcomeGuard.reason(intent_dir, "delivered")
    refute_nil refusal, "OutcomeGuard must still refuse: scaffold-intent must never pick a disposition"
  end

  # --- 11: outcome writes no Done briefing and no self-naming banner ---------------

  def test_outcome_has_no_done_briefing_or_self_naming_banner
    intent_dir = build_intent
    result = ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: false, store: @store,
                                             id: "213z", runner: FakeRunner.new, home: @home)
    written = File.read(result[:path])
    refute_includes written, "Done briefing"
    refute_includes written, "## Outcome"
    refute written.lines.any? { |l| l.start_with?("Announce") }
  end

  # --- 12/13/14: the --force guard, all three subcommands --------------------------

  def test_refuses_to_overwrite_real_content_without_force
    intent_dir = build_intent
    target = File.join(intent_dir, "spec.md")
    File.write(target, "# Spec: real content already written\n")
    original = File.read(target)

    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    assert_equal 2, result[:code]
    assert_equal original, File.read(target)
  end

  def test_checklist_refuses_to_overwrite_real_content_without_force
    intent_dir = build_intent
    write_spec(intent_dir)
    target = File.join(intent_dir, "checklist.md")
    File.write(target, "# Checklist: real content already written\n")
    original = File.read(target)

    result = ScaffoldIntent.scaffold_checklist(intent_dir: intent_dir, force: false)
    assert_equal 2, result[:code]
    assert_equal original, File.read(target)
  end

  def test_outcome_refuses_to_overwrite_real_content_without_force
    intent_dir = build_intent
    target = File.join(intent_dir, "outcome.md")
    File.write(target, "---\ndisposition: delivered\n---\n# Outcome: real content already written\n")
    original = File.read(target)

    result = ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: false, store: @store,
                                             id: "213z", runner: FakeRunner.new, home: @home)
    assert_equal 2, result[:code]
    assert_equal original, File.read(target)
  end

  def test_overwrites_a_sentinel_only_target_without_force
    intent_dir = build_intent
    target = File.join(intent_dir, "spec.md")
    File.write(target, "#{SENTINEL}\n")

    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: false)
    assert_equal :ok, result[:status]
    refute_equal "#{SENTINEL}\n", File.read(target)
  end

  def test_force_overwrites_real_content
    intent_dir = build_intent
    target = File.join(intent_dir, "spec.md")
    File.write(target, "# Spec: real content already written\n")

    result = ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: true)
    assert_equal :ok, result[:status]
    refute_equal "# Spec: real content already written\n", File.read(target)
  end

  # --- 15: no subcommand ever creates actions/ --------------------------------------

  def test_no_subcommand_creates_actions_dir
    intent_dir = build_intent
    write_spec(intent_dir)

    ScaffoldIntent.scaffold_spec(intent_dir: intent_dir, force: true)
    ScaffoldIntent.scaffold_checklist(intent_dir: intent_dir, force: true)
    ScaffoldIntent.scaffold_outcome(intent_dir: intent_dir, force: true, store: @store,
                                    id: "213z", runner: FakeRunner.new, home: @home)

    refute Dir.exist?(File.join(intent_dir, "actions"))
  end

  # --- 16: usage failures exit 1, driven through the real subprocess ---------------

  def test_usage_failures_exit_1
    intent_dir = build_intent
    write_spec(intent_dir)
    intent_dir_two = File.join(@store, "213z--another")
    _out, status = run_scaffold("bogus", "--store", @store, "--id", "213z")
    assert_equal 1, status, "unknown subcommand"

    _out, status = run_scaffold("spec", "--id", "213z")
    assert_equal 1, status, "missing --store"

    _out, status = run_scaffold("spec", "--store", @store)
    assert_equal 1, status, "missing --id"

    _out, status = run_scaffold("spec", "--store", @store, "--id", "nope")
    assert_equal 1, status, "id matches no directory"

    FileUtils.mkdir_p(intent_dir_two)
    _out, status = run_scaffold("spec", "--store", @store, "--id", "213z")
    assert_equal 1, status, "id matches two directories"
    FileUtils.rm_rf(intent_dir_two)

    _out, status = run_scaffold("spec", "--store", @store, "--id", "213z", "--test-summary", "/tmp/x")
    assert_equal 1, status, "--test-summary on spec"

    _out, status = run_scaffold("checklist", "--store", @store, "--id", "213z", "--test-summary", "/tmp/x")
    assert_equal 1, status, "--test-summary on checklist"

    missing_ts = File.join(@home, "does-not-exist.txt")
    _out, status = run_scaffold("outcome", "--store", @store, "--id", "213z", "--test-summary", missing_ts)
    assert_equal 1, status, "--test-summary naming a nonexistent path"
  end

  # --- happy path end to end, through the real CLI (real templates, real exit 0) ---

  def test_happy_path_through_the_real_cli_exits_zero
    intent_dir = build_intent(id: "213y", slug: "cli")

    out, status = run_scaffold("spec", "--store", @store, "--id", "213y")
    assert_equal 0, status, out
    assert Savepoint.stage_file_present?(File.join(intent_dir, "spec.md"))

    out, status = run_scaffold("checklist", "--store", @store, "--id", "213y")
    assert_equal 0, status, out
    assert Savepoint.stage_file_present?(File.join(intent_dir, "checklist.md"))
  end
end
