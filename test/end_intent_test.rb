# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "date"
require "json"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"

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
    @tmp_bridge = Dir.mktmpdir("end-intent-bridge")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp_bridge)
  end

  # Isolates the child's environment (no ambient CLAUDE_CODE_SESSION_ID, a
  # dedicated PLASTIC_TMP) because end-intent now calls Bridge.read /
  # Bridge.disarm_auto unconditionally on every invocation, even a no-op
  # session (intent 188): relying on non-collision with the REAL /tmp bridge
  # is exactly the fragility test/hermeticity_guard_test.rb forbids, and that
  # static guard cannot see this risk (it scans test source, never the
  # subprocess this file spawns). `session:` is appended as `--session` only
  # when given, so every pre-188 call site (no session:) is unaffected beyond
  # the env isolation itself.
  def run_end_intent(*args, session: nil)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    argv = session ? args + ["--session", session] : args
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *argv], err: [:child, :out], &:read)
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

  # Write a minimal, valid bridge JSON for `session`/`id` directly into the
  # isolated @tmp_bridge dir (never through the real arm/auto seam - these
  # fixtures stay fully hermetic and never touch the real /tmp). No "worktree" key by
  # default, so Worktree.release's real git/HOME resolution is never reached
  # (see scripts/lib/worktree.rb: `return bridge_data unless block.is_a?(Hash)`).
  def write_bridge(session:, id:, slug: "demo")
    data = {
      "session" => session,
      "intent" => { "id" => id, "dir" => "#{id}--#{slug}", "store" => @store, "name" => slug },
      "build" => { "auto" => false },
      "lock" => { "owner_session" => session, "acquired_at" => Time.now.utc.iso8601,
                  "host" => "test", "type" => "delivery", "delegates" => [] },
    }
    File.write(File.join(@tmp_bridge, "plastic-#{session}--#{id}.json"), JSON.pretty_generate(data))
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

  # --- --index-note appends the rich Completed/Abandoned entry [AC5, F3] -----

  def test_index_note_appends_the_rich_entry_description
    build_intent
    write_index

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                   "--index", @index, "--no-commit",
                                   "--index-note", "(guided, Tier S). Shipped end to end. Suite 42/100/0/0.")
    assert_equal 0, status

    content = File.read(@index)
    expected_line = "- [161 — Demo intent](store/161--demo/161--demo.md) — " \
                    "#{Date.today.iso8601} (guided, Tier S). Shipped end to end. Suite 42/100/0/0.\n"
    assert_includes content, expected_line
    completed_head = content.lines.drop_while { |l| l.strip != "## Completed" }.take(3).join
    refute_match(/_\(none\)_/, completed_head, "the placeholder must not survive alongside the rich entry")
  end

  def test_index_note_idempotency_holds_with_the_flag
    build_intent
    write_index
    note = "(guided, Tier S). Shipped end to end. Suite 42/100/0/0."

    run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                    "--index", @index, "--no-commit", "--index-note", note)
    after_first = File.read(@index)

    _out, status2 = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                    "--index", @index, "--no-commit", "--index-note", note)
    assert_equal 0, status2
    after_second = File.read(@index)
    assert_equal after_first, after_second, "a second run with the same --index-note must be a clean no-op"
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

  # --- AC1: a normal close clears the delivery lock ---------------------------

  def test_ac1_normal_delivered_close_clears_the_delivery_lock
    intent_dir = build_intent(id: "161")
    write_index(id: "161")
    Lock.acquire(intent_dir, session: "sess-1")
    write_bridge(session: "sess-1", id: "161")

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                   "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status
    refute File.exist?(Lock.path(intent_dir)), "AC1: exit 0 must imply no delivery.lock remains"
  end

  def test_ac1_normal_abandoned_close_clears_the_delivery_lock
    intent_dir = build_intent(id: "161", outcome_disposition: "abandoned")
    write_index(id: "161")
    Lock.acquire(intent_dir, session: "sess-1")
    write_bridge(session: "sess-1", id: "161")

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "abandoned",
                                   "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status
    refute File.exist?(Lock.path(intent_dir))
  end

  # --- AC2: fresh foreign lock refuses; stale foreign lock is taken over ------

  def test_ac2_fresh_foreign_lock_refuses_before_any_writes
    intent_dir = build_intent(id: "161")
    write_index(id: "161")
    Lock.acquire(intent_dir, session: "owner-session")
    before_index = File.read(@index)
    before_intent_file = File.read(Bridge.intent_file(intent_dir))
    before_outcome = File.read(File.join(intent_dir, "outcome.md"))

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                  "--index", @index, "--no-commit", session: "someone-else")
    assert_equal 4, status
    assert_match(/held/i, out)
    assert_equal before_index, File.read(@index), "INDEX.md must be left untouched"
    assert_equal before_intent_file, File.read(Bridge.intent_file(intent_dir))
    assert_equal before_outcome, File.read(File.join(intent_dir, "outcome.md"))
    assert_empty savepoint_lines(intent_dir), "savepoint.md must be left untouched"
    assert File.exist?(Lock.path(intent_dir)), "the foreign lock must be left exactly as found"
  end

  def test_ac2_stale_foreign_lock_is_taken_over_and_closes_normally
    intent_dir = build_intent(id: "161")
    write_index(id: "161")
    Lock.acquire(intent_dir, session: "owner-session")
    FileUtils.touch(Lock.path(intent_dir), mtime: Time.now - 4000) # older than Lock::TTL_SECONDS (1800)
    write_bridge(session: "someone-else", id: "161")

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                   "--index", @index, "--no-commit", session: "someone-else")
    assert_equal 0, status

    lines = savepoint_lines(intent_dir)
    assert(lines.any? { |l| l.include?("Lock") && l.include?("takeover") && l.include?("someone-else") },
           "expected an audited takeover line: #{lines.inspect}")
    refute File.exist?(Lock.path(intent_dir)), "a normal close clears the lock even after takeover"
  end

  # --- AC3 (re-shaped, see intent 188 executor corrections): the direct lock- --
  # --- release fallback cannot resolve a corrupt lock; a second run after ----
  # --- an external fix is idempotent ------------------------------------------
  #
  # Correction 1 makes end-intent's step 5 fall back to releasing the durable
  # delivery.lock directly (by its OWN recorded owner_session) whenever the
  # /tmp bridge cannot resolve (Bridge.disarm_auto no-ops entirely in that
  # case). That fallback always uses the lock's own owner field, so a
  # caller-session mismatch can never make it fail (D4's pre-flight has
  # already established the caller is the owner, a delegate, or the
  # post-takeover owner by this point). The one honest way the fallback
  # itself cannot resolve the lock is a CORRUPT lock file (unparseable JSON,
  # the same "run /plastic-lock fix" case AGENTS.md already names): its
  # owner_session cannot be read at all, so the direct release is skipped,
  # and the still-present lock file makes end-intent exit 3.
  def test_ac3_corrupt_lock_cannot_be_directly_released_exits_3_then_idempotent_retry_exits_0
    intent_dir = build_intent(id: "161")
    write_index(id: "161")
    File.write(Lock.path(intent_dir), "{ not valid json")
    # Deliberately NO write_bridge call: disarm_auto no-ops (no bridge to resolve).

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                  "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 3, status
    assert_match(/still present/i, out)
    assert File.exist?(Lock.path(intent_dir)), "a corrupt lock's owner cannot be resolved: it must still be present"

    File.delete(Lock.path(intent_dir)) # simulate an external fix (plastic-lock fix, or a takeover)

    out2, status2 = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                    "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status2, "a second run after the block clears must finish idempotently: #{out2}"
    refute File.exist?(Lock.path(intent_dir))
  end

  # --- AC13 (new, intent 188 executor correction 1): no bridge resolves at ----
  # --- all, but the lock IS owned by the resolved session: the durable lock --
  # --- is released directly, LOUDLY (the /tmp bridge is only a cache; a -------
  # --- wiped /tmp or a resumed job under a new session id must never strand --
  # --- a committed, terminal intent still holding its lock) ------------------

  def test_ac13_no_bridge_at_all_still_clears_an_owned_lock_with_a_loud_warning
    intent_dir = build_intent(id: "161")
    write_index(id: "161")
    Lock.acquire(intent_dir, session: "sess-1")
    # Deliberately NO write_bridge call: the /tmp bridge cannot resolve at all
    # (a wiped /tmp, or a resumed job running under a new session id).

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                  "--index", @index, "--no-commit", session: "sess-1")
    assert_equal 0, status, "AC13: no bridge must still exit 0 when the lock is directly releasable: #{out}"
    refute File.exist?(Lock.path(intent_dir)), "AC13: the durable lock must be cleared even with no bridge"
    assert_match(/no bridge resolved/i, out)
    assert_match(/NOT removed/i, out)
    assert_match(/orphaned worktree/i, out)
  end

  # --- AC4: a hyphen Active line moves; the write still emits a real em dash --

  def test_ac4_hyphen_active_line_moves_and_still_emits_em_dash_on_write
    build_intent(id: "161")
    File.write(@index, <<~MD)
      # Index

      ## Active
      - [161 - Demo intent](store/161--demo/161--demo.md) - a demo intent for the test suite

      ## Completed
      _(none)_

      ## Abandoned
      _(none)_
    MD

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                   "--index", @index, "--no-commit")
    assert_equal 0, status
    content = File.read(@index)
    refute_match(/^- \[161 /, content.lines.take_while { |l| l.strip != "## Completed" }.join,
                 "the hyphen-formatted Active entry must still be recognized and moved")
    assert_match(/^## Completed\n- \[161 — Demo intent\]\(store\/161--demo\/161--demo\.md\) — \d{4}-\d{2}-\d{2}/,
                 content, "the terminal entry must be written with a real em dash regardless of input separator")
  end

  # --- AC5: unresolved id is loud (exit 1); already-terminal id is quiet (exit 0) --

  def test_ac5_unresolved_id_exits_1
    build_intent(id: "161")
    File.write(@index, <<~MD)
      # Index

      ## Active
      _(none)_

      ## Completed
      _(none)_

      ## Abandoned
      _(none)_
    MD

    out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                  "--index", @index, "--no-commit")
    assert_equal 1, status
    assert_match(/could not be resolved/i, out)
  end

  def test_ac5_id_already_in_terminal_section_is_a_quiet_success
    build_intent(id: "161")
    File.write(@index, <<~MD)
      # Index

      ## Active
      _(none)_

      ## Completed
      - [161 — Demo intent](store/161--demo/161--demo.md) — 2026-07-01

      ## Abandoned
      _(none)_
    MD
    before = File.read(@index)

    _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered",
                                   "--index", @index, "--no-commit")
    assert_equal 0, status
    assert_equal before, File.read(@index), "an id already in the terminal section must be an untouched no-op"
  end
end
