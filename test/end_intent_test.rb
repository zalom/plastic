# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/bridge"

# end-intent (intent 161): the mechanical core of the Done procedure (D2 steps
# 1-4). Drives the real script as a subprocess against a hermetic tmp home
# (own store + own INDEX.md), mirroring test/new_intent_test.rb's house style.
# No eval, no ambient session id, no PLASTIC_TMP touched (end-intent writes no
# bridge state, so the hermeticity guard's WRITERS pattern does not apply, but
# every fixture still lives under Dir.mktmpdir).
class EndIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/end-intent", __dir__)
  SENTINEL = Bridge::PLACEHOLDER_SENTINEL

  def setup
    @home = Dir.mktmpdir("end-intent-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @index = File.join(@home, "INDEX.md")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def run_end_intent(*args)
    out = IO.popen([RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  # --- fixture builders ------------------------------------------------------

  def build_intent(id: "161", slug: "demo", outcome_disposition: "delivered", sentinel: false)
    intent_dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "Demo intent"
      sources: []
      chain: []
      created: 2026-07-01
      author: human
      tags: []
      ---

      ## Intent
      Demo intent

      ## Context

      ## Outcome
      (the result)

      ## Insights

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD

    outcome = +""
    outcome << "#{SENTINEL}\n" if sentinel
    outcome << "---\ndisposition: #{outcome_disposition}\n---\n" \
               "# Outcome: Demo intent\n\n## Summary\nDid the thing.\n"
    File.write(File.join(intent_dir, "outcome.md"), outcome)

    intent_dir
  end

  def write_index(id: "161", slug: "demo", title: "Demo intent")
    File.write(@index, <<~MD)
      # Index

      ## Active
      - [#{id} — #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md) — a demo intent for the test suite

      ## Completed
      _(none)_

      ## Abandoned
      _(none)_
    MD
  end

  def savepoint_lines(intent_dir)
    path = File.join(intent_dir, "savepoint.md")
    File.exist?(path) ? File.read(path).lines.map(&:strip).reject(&:empty?) : []
  end

  # --- (a) Done bookend lands once and is idempotent [AC3] -------------------

  def test_done_bookend_lands_once_and_is_idempotent
    intent_dir = build_intent
    write_index

    _out, status1 = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                    "--index", @index, "--no-commit")
    assert_equal 0, status1

    done_lines = savepoint_lines(intent_dir).grep(/\bDone\b/)
    assert_equal 1, done_lines.length, "expected exactly one Done line: #{savepoint_lines(intent_dir).inspect}"
    assert_match(/Done\s+delivered/, done_lines.first)

    _out2, status2 = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                     "--index", @index, "--no-commit")
    assert_equal 0, status2

    done_lines_after = savepoint_lines(intent_dir).grep(/\bDone\b/)
    assert_equal 1, done_lines_after.length, "a second run must not duplicate the Done bookend"
  end

  # --- (b) missing / placeholder / wrong-disposition outcome.md -> exit 2 [AC4] --

  def test_missing_outcome_refuses_with_exit_2_and_no_done_line
    intent_dir = File.join(@store, "161--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "161--demo.md"), "## Intent\nDemo\n")
    write_index

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index)
    assert_equal 2, status
    assert_match(/missing/i, out)
    assert_empty savepoint_lines(intent_dir)
  end

  def test_placeholder_outcome_refuses_with_exit_2_and_no_done_line
    intent_dir = build_intent(sentinel: true, outcome_disposition: "delivered|abandoned")
    write_index

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index)
    assert_equal 2, status
    assert_match(/placeholder/i, out)
    assert_empty savepoint_lines(intent_dir)
  end

  def test_scaffolded_outcome_is_refused_by_the_disposition_literal_too
    # Belt-and-braces: even without the sentinel, the scaffold's literal
    # "delivered|abandoned" frontmatter value fails the exact-match check.
    intent_dir = build_intent(outcome_disposition: "delivered|abandoned")
    write_index

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index)
    assert_equal 2, status
    assert_match(/disposition/i, out)
    assert_empty savepoint_lines(intent_dir)
  end

  def test_wrong_disposition_outcome_refuses_with_exit_2_and_no_done_line
    intent_dir = build_intent(outcome_disposition: "abandoned")
    write_index

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index)
    assert_equal 2, status
    assert_match(/disposition/i, out)
    assert_empty savepoint_lines(intent_dir)
  end

  # --- (c) INDEX line moves Active -> terminal, idempotently [AC5] -----------

  def test_index_line_moves_active_to_completed_and_second_run_is_noop
    build_intent
    write_index

    run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index, "--no-commit")
    after_first = File.read(@index)

    refute_match(/^- \[161 /, after_first.lines.take_while { |l| l.strip != "## Completed" }.join,
                 "the Active section must no longer carry the 161 entry")
    assert_match(/^## Completed\n- \[161 — Demo intent\]\(store\/161--demo\/161--demo\.md\) — \d{4}-\d{2}-\d{2}/,
                 after_first)

    _out, status2 = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                    "--index", @index, "--no-commit")
    assert_equal 0, status2
    after_second = File.read(@index)
    assert_equal after_first, after_second, "a second run must be a clean no-op on INDEX.md"
    assert_equal 1, after_second.scan("[161").length, "no duplicate entry after the second run"
  end

  def test_abandoned_disposition_moves_to_abandoned_section
    build_intent(outcome_disposition: "abandoned")
    write_index

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "abandoned",
                                   "--index", @index, "--no-commit")
    assert_equal 0, status
    content = File.read(@index)
    assert_match(/^## Abandoned\n- \[161 /, content)
    refute_match(/^## Completed\n- \[161 /, content)
  end

  # --- (d) --dry-run changes nothing ------------------------------------------

  def test_dry_run_changes_nothing
    intent_dir = build_intent
    write_index
    intent_file = Bridge.intent_file(intent_dir)
    outcome_file = File.join(intent_dir, "outcome.md")

    before_intent = File.read(intent_file)
    before_outcome = File.read(outcome_file)
    before_index = File.read(@index)

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                  "--index", @index, "--dry-run")
    assert_equal 0, status
    refute_empty out

    assert_equal before_intent, File.read(intent_file)
    assert_equal before_outcome, File.read(outcome_file)
    assert_equal before_index, File.read(@index)
    refute File.exist?(File.join(intent_dir, "savepoint.md")), "dry-run must not append the savepoint bookend"
  end

  # --- (e) store auto-commit lands with a real git repo -----------------------

  def test_store_commit_lands_in_a_real_git_repo
    build_intent
    write_index
    Open3.capture3("git", "init", "-q", @home)

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index)
    assert_equal 0, status

    log, _err, log_status = Open3.capture3("git", "-C", @home, "log", "--oneline")
    assert log_status.success?
    assert_match(/complete intent 161/, log)

    status_out, = Open3.capture3("git", "-C", @home, "status", "--porcelain")
    assert_empty status_out.strip, "the store commit must leave the working tree clean"
  end

  def test_no_commit_flag_skips_the_store_commit
    build_intent
    write_index
    Open3.capture3("git", "init", "-q", @home)

    run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index, "--no-commit")

    log, = Open3.capture3("git", "-C", @home, "log", "--oneline")
    assert_empty log.strip, "--no-commit must leave the store repo with no commits"
  end

  # --- outcome-summary stamp (D2 step 1b) -------------------------------------

  def test_outcome_summary_stamps_the_intent_file_outcome_section
    intent_dir = build_intent
    write_index

    run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index,
                    "--no-commit", "--outcome-summary", "Shipped the demo end to end.")

    body = File.read(Bridge.intent_file(intent_dir))
    assert_includes body, "## Outcome\nShipped the demo end to end.\n"
  end

  # --- usage / resolution errors [D2, exit 1] ---------------------------------

  def test_unknown_id_exits_1
    write_index
    _out, status = run_end_intent("--store", @store, "--id", "999", "--disposition", "delivered", "--index", @index)
    assert_equal 1, status
  end

  def test_missing_required_args_exits_1
    _out, status = run_end_intent("--id", "161", "--disposition", "delivered")
    assert_equal 1, status
  end

  def test_bad_disposition_exits_1
    build_intent
    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "bogus")
    assert_equal 1, status
  end
end
