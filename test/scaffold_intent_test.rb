# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/scaffold_intent"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/outcome_guard"

# scaffold-intent (intent 213; one `backfill` verb since intent 308): drives the real
# SCRIPT as a subprocess for the exit-code contract and the surviving ScaffoldIntent
# helpers in process. The writer's own logic is covered by test/backfill_intent_test.rb.
# Hermetic: every fixture lives under Dir.mktmpdir, no eval, no network, no ambient
# session id, no real ~/.plastic read.
class ScaffoldIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/scaffold-intent", __dir__)
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL

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

  DECISIONS_BODY = <<~MD.freeze
    - First decision, plain.
    - Second decision that wraps across
      a continuation line for wrapped-line testing.
  MD

  def build_intent(id: "213z", slug: "demo", sentinel_docs: true)
    intent_dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(File.join(intent_dir, "actions"))
    File.write(File.join(intent_dir, "actions", ".gitkeep"), "")
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
      Some context prose.

      ### Decisions
      #{DECISIONS_BODY}
      ## Outcome
      (placeholder)

      ## Insights

      ## Links
      (placeholder)
    MD
    File.write(File.join(intent_dir, "checklist.md"), "# Checklist\n\n## Completed\n- [x] Step 1 - did it\n")
    if sentinel_docs
      %w[spec.md plan.md outcome.md].each { |f| File.write(File.join(intent_dir, f), "#{SENTINEL}\n") }
    end
    intent_dir
  end

  def run_scaffold(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  # --- the backfill verb through the real CLI ----------------------------------------

  def test_backfill_writes_the_placeholder_documents_and_exits_zero
    intent_dir = build_intent
    out, status = run_scaffold("backfill", "--store", @store, "--id", "213z",
                               "--disposition", "delivered", "--summary", "Shipped.")

    assert_equal 0, status, out
    %w[spec.md plan.md actions/ACTION_1.md outcome.md].each do |rel|
      assert_match(/backfilled .*#{Regexp.escape(rel)}/, out)
      assert Savepoint.stage_file_present?(File.join(intent_dir, rel)), "#{rel} must be real"
    end
    spec = File.read(File.join(intent_dir, "spec.md"))
    assert_includes spec, "## Decisions\n#{DECISIONS_BODY}"
    assert_nil OutcomeGuard.reason(intent_dir, "delivered")
    assert_includes File.read(File.join(intent_dir, "outcome.md")), "## Summary\nShipped.\n"
  end

  def test_backfill_keeps_real_content_and_reports_nothing_to_do
    intent_dir = build_intent(sentinel_docs: false)
    real = { "spec.md" => "# Spec: mine\n", "plan.md" => "# Plan: mine\n",
             "outcome.md" => "---\ndisposition: abandoned\n---\n# Outcome: mine\n\n## Summary\nmine\n",
             "actions/ACTION_1.md" => "# ACTION_1: mine\n" }
    real.each { |rel, body| File.write(File.join(intent_dir, rel), body) }

    out, status = run_scaffold("backfill", "--store", @store, "--id", "213z", "--disposition", "delivered")

    assert_equal 0, status, out
    assert_match(/nothing to backfill/, out)
    real.each { |rel, body| assert_equal body, File.read(File.join(intent_dir, rel)), "#{rel} must be untouched" }
  end

  def test_backfill_with_a_missing_intent_file_exits_3_and_writes_nothing
    intent_dir = build_intent
    File.delete(File.join(intent_dir, "213z--demo.md"))

    out, status = run_scaffold("backfill", "--store", @store, "--id", "213z", "--disposition", "delivered")

    assert_equal 3, status, out
    assert_match(/intent file is missing/, out)
    assert_equal "#{SENTINEL}\n", File.read(File.join(intent_dir, "spec.md"))
  end

  # --- usage contract -----------------------------------------------------------------

  def test_usage_failures_exit_1
    build_intent
    cases = {
      "old spec verb" => ["spec", "--store", @store, "--id", "213z"],
      "old checklist verb" => ["checklist", "--store", @store, "--id", "213z"],
      "old outcome verb" => ["outcome", "--store", @store, "--id", "213z"],
      "no subcommand" => [],
      "missing --store" => ["backfill", "--id", "213z", "--disposition", "delivered"],
      "missing --id" => ["backfill", "--store", @store, "--disposition", "delivered"],
      "missing --disposition" => ["backfill", "--store", @store, "--id", "213z"],
      "bad --disposition" => ["backfill", "--store", @store, "--id", "213z", "--disposition", "done"],
      "--force is gone" => ["backfill", "--store", @store, "--id", "213z", "--disposition", "delivered", "--force"],
      "--test-summary is gone" => ["backfill", "--store", @store, "--id", "213z", "--disposition", "delivered",
                                   "--test-summary", "/dev/null"],
      "unknown id" => ["backfill", "--store", @store, "--id", "999", "--disposition", "delivered"],
      "missing store" => ["backfill", "--store", File.join(@home, "nope"), "--id", "213z", "--disposition", "delivered"],
    }
    cases.each do |label, argv|
      out, status = run_scaffold(*argv)
      assert_equal 1, status, "#{label}: #{out}"
      assert_match(/usage: scaffold-intent backfill/, out, label)
    end
  end

  def test_no_verb_creates_a_second_action_when_a_real_one_exists
    intent_dir = build_intent
    File.write(File.join(intent_dir, "actions", "ACTION_2.md"), "# ACTION_2: mine\n")
    _out, status = run_scaffold("backfill", "--store", @store, "--id", "213z", "--disposition", "delivered")

    assert_equal 0, status
    refute File.exist?(File.join(intent_dir, "actions", "ACTION_1.md"))
  end

  # --- the surviving helpers ------------------------------------------------------------

  def test_removed_scaffold_functions_are_gone_and_shared_helpers_stay
    %i[scaffold_spec build_spec_content scaffold_checklist extract_acceptance_criteria
       scaffold_outcome refuse_without_force? refuse_result].each do |m|
      refute ScaffoldIntent.respond_to?(m), "ScaffoldIntent.#{m} was removed in 2.0 (intent 308)"
    end
    refute ScaffoldIntent.const_defined?(:SPEC_SECTIONS)
    %i[expand resolve_intent_dir resolve_templates_dir sections_from replace_section_body
       extract_decisions strip_blank_edges resolve_repo_dir detect_base_branch diffstat
       build_verification_body].each do |m|
      assert ScaffoldIntent.respond_to?(m), "ScaffoldIntent.#{m} must survive for its callers"
    end
  end

  def test_extract_decisions_is_byte_for_byte_and_errors_without_the_heading
    body, err = ScaffoldIntent.extract_decisions("## Context\nx\n\n### Decisions\n#{DECISIONS_BODY}\n## Outcome\n")
    assert_nil err
    assert_equal DECISIONS_BODY, body

    body2, err2 = ScaffoldIntent.extract_decisions("## Context\nno decisions here\n")
    assert_nil body2
    assert_match(/no ### Decisions/, err2)
  end

  def test_resolve_intent_dir_rejects_ambiguity_and_misses
    build_intent(id: "9a", slug: "one")
    build_intent(id: "9a", slug: "two")
    dir, err = ScaffoldIntent.resolve_intent_dir(@store, "9a")
    assert_nil dir
    assert_match(/ambiguous/, err)

    dir2, err2 = ScaffoldIntent.resolve_intent_dir(@store, "8z")
    assert_nil dir2
    assert_match(/no intent directory/, err2)
  end
end
