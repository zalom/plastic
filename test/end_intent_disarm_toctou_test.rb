# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"
# `load`, not `require_relative`: the script has no .rb suffix, and Ruby's
# require/require_relative feature resolution refuses to load an extension-
# less path even when it exists on disk (require needs a recognized
# extension to resolve a "loadable feature"; `load` has no such restriction,
# it just evaluates the exact given path). `main(ARGV) if $PROGRAM_NAME ==
# __FILE__` at the bottom of the script still guards against running `main`
# here, exactly as it does under `require`.
load File.expand_path("../scripts/end-intent", __dir__)

# run_disarm's direct-lock-release fallback, in-process (post-review hardening,
# intent 188, second reviewer pass). This scenario cannot be reproduced by
# spawning the real script as a subprocess (test/end_intent_test.rb's house
# style): it needs an interleaving point BETWEEN "disarm ran" and "verify the
# lock is gone" where a DIFFERENT session's lock has appeared, and only
# run_disarm's own injected `disarm:` seam gives us a hook at that exact
# moment. A separate file, not test/end_intent_test.rb: this is the one place
# in the suite that requires the flat script directly (defining its top-level
# helpers in-process) instead of driving it as a subprocess, so it is kept
# isolated rather than risking a silent method collision with any other test
# file's fixtures. `$PROGRAM_NAME == __FILE__` in the script's own trailing
# line means requiring it here never runs its `main`.
class EndIntentDisarmToctouTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("end-intent-toctou-home")
    @intent_dir = File.join(@home, "161--demo")
    FileUtils.mkdir_p(@intent_dir)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # The TOCTOU bug this test pins: no lock exists yet (pre-flight proceeded
  # legitimately), then a DIFFERENT, live session acquires the lock during
  # this exact close (simulated here by the fake `disarm:` seam, which stands
  # in for the real disarm call's own window of vulnerability). The
  # first-draft fallback read that lock's own recorded owner and handed it
  # straight back to Lock.release, which is a vacuous ownership check
  # (comparing a value to itself), so it deleted the OTHER session's fresh
  # lock and silently broke mutual exclusion. The fix must refuse instead.
  def test_a_lock_acquired_by_another_session_during_close_is_never_deleted
    refute File.exist?(Lock.path(@intent_dir)), "no lock exists yet: this is the pre-flight-proceeded case"

    racer_disarm = lambda do |_sess, _dir|
      # Stands in for the real disarm call's window of vulnerability: another
      # live session acquires the delivery lock WHILE this close is running.
      Lock.acquire(@intent_dir, session: "attacker-session")
      nil
    end

    result = run_disarm(@intent_dir, "161", "sess-1", discard_worktree_changes: false,
                         worktree_reader: ->(_dir) { nil },
                         disarm: racer_disarm)

    assert_equal :lock_remains, result, "a foreign lock acquired mid-close must never be silently deleted"
    assert File.exist?(Lock.path(@intent_dir)), "BLOCKER (TOCTOU): the racing session's lock file must survive"
    lock = Lock.read(@intent_dir)
    assert_equal "attacker-session", lock["owner_session"],
                 "the lock on disk must still be the OTHER session's, untouched"
  end

  # Confirms the fix's own escape hatch is not over-tight: a registered
  # delegate (Lock.authorized? honors the delegates array, not just a raw
  # owner_session equality check) can still close and clear the lock, exactly
  # as before this hardening.
  def test_delegate_session_can_still_close_and_clear_the_lock
    Lock.acquire(@intent_dir, session: "owner-session")
    Lock.add_delegate(@intent_dir, delegate: "delegate-session", session: "owner-session")

    result = run_disarm(@intent_dir, "161", "delegate-session", discard_worktree_changes: false,
                         worktree_reader: ->(_dir) { nil },
                         disarm: ->(_sess, _dir) { nil })

    assert_equal :ok, result, "a legitimate delegate close must still succeed"
    refute File.exist?(Lock.path(@intent_dir)), "a delegate close must clear the lock, same as the owner"
  end

  # The ordinary, non-racing owner path still works exactly as before: the
  # owner's own lock is present at step 5, Lock.authorized? matches it
  # directly, and it is released normally.
  def test_owner_session_can_still_close_and_clear_its_own_lock
    Lock.acquire(@intent_dir, session: "sess-1")

    result = run_disarm(@intent_dir, "161", "sess-1", discard_worktree_changes: false,
                         worktree_reader: ->(_dir) { nil },
                         disarm: ->(_sess, _dir) { nil })

    assert_equal :ok, result
    refute File.exist?(Lock.path(@intent_dir))
  end

  # --- structure gate fail-open on a crash (intent 222, D4) -------------------
  #
  # The per-intent doctor gate end-intent's main calls before any write (run_structure_gate,
  # scripts/end-intent) must never let a crash inside the gate call itself wedge a close: an
  # unexpected exception is rescued, logged, and treated as a skipped gate. This cannot be
  # reproduced by spawning the real script as a subprocess (test/end_intent_test.rb's house
  # style): there is no eval/ENV/global seam available to make the gate crash from outside a
  # fresh child process without an actual on-disk trigger, and the one genuine trigger this
  # codebase has (resolve_single_intent_dir's cross-store ambiguity RuntimeError) collides
  # with end-intent's OWN, earlier resolve_intent_dir call whenever the decoy sits in the
  # same --store directory, since both scan that literal directory for "id--*" first. Only
  # run_structure_gate's own injected `gate:` seam (mirrors run_disarm's worktree_reader:/
  # disarm: pattern above) gives a deterministic hook, exactly like every other test in this
  # file - hence its home here, not test/end_intent_test.rb (this file's own header comment
  # already reserves it as the one place that loads the script in-process).
  def test_structure_gate_crash_is_rescued_and_never_exits_or_raises
    crashing_gate = ->(_gate_home, _gate_scope) { raise "boom (test-injected doctor crash)" }

    _stdout, stderr = capture_io do
      run_structure_gate("161", store: File.join(@home, "store"), gate: crashing_gate)
    end

    assert_match(/structure gate crashed/i, stderr)
    assert_match(/boom \(test-injected doctor crash\)/, stderr)
  end

  # A clean ("pass") verdict from the gate proceeds silently: no stderr output, no exit.
  def test_structure_gate_pass_verdict_proceeds_silently
    passing_gate = ->(_gate_home, _gate_scope) { { status: "pass", checks: [] } }

    stdout, stderr = capture_io do
      run_structure_gate("161", store: File.join(@home, "store"), gate: passing_gate)
    end

    assert_empty stdout
    assert_empty stderr
  end

  # A "warn" verdict prints the advisory and proceeds (never exits): matches intent 134's
  # advisory-only doctrine for intent_savepoint_truthful.
  def test_structure_gate_warn_verdict_prints_and_proceeds
    warn_check = { name: "intent_savepoint_truthful", status: "warn", message: "savepoint.md is missing" }
    warning_gate = ->(_gate_home, _gate_scope) { { status: "warn", checks: [warn_check] } }

    _stdout, stderr = capture_io do
      run_structure_gate("161", store: File.join(@home, "store"), gate: warning_gate)
    end

    assert_match(/structure gate warning \(proceeding\)/i, stderr)
    assert_match(/savepoint\.md is missing/i, stderr)
  end
end
