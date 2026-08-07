# encoding: UTF-8
# frozen_string_literal: true

require "open3"
require_relative "bridge"
require_relative "lock"
require_relative "worktree"
require_relative "scaffold_intent"

# ExecWorktree - all logic for `scripts/exec-worktree` (intent 213, group 2). Finish an
# intent's code worktree: an order precondition, then `Worktree.finish` (delivered merges
# and removes, abandoned removes only).
#
# THIS IS THE HIGHEST-RISK SURFACE IN THIS ACTION SET because it composes worktree
# arbitration. The rule for that surface is compose the existing primitives, add nothing
# (spec D6).
#
# NEVER REIMPLEMENTS WORKTREE ARBITRATION. `Worktree.finish` (scripts/lib/worktree.rb:225)
# already does merge-then-remove or remove-only, fail-open, idempotent throughout. This
# module writes no git worktree, merge, or branch mechanics of its own, and never calls
# either of the Lock module's release or takeover operations (that unguarded
# read-modify-write gap is parked intent 254's territory).
#
# THE ORDER-PRECONDITION TRAP (spec D7, binding). `Bridge.code_gate_decision` returns nil
# UNCONDITIONALLY when the bridge is guided (`build["auto"] != true`), so as a precondition
# it is VACUOUS in guided mode. This module calls that predicate exactly as it exists,
# unmodified, and never copies its "reached How" body into a second predicate (the 200/204
# duplication failure pattern). Instead it states plainly, in the printed output, that on a
# guided bridge the precondition is advisory only, and that the hook layer
# (`Bridge.code_gate_decision`, wired through `scripts/lib/edit_gates.rb`) remains the
# actual enforcement point.
#
# Pure and dependency-injected: never calls `exit` or `abort`, never reads `ARGV` directly.
# Seams: `runner:` (git, defaults to `Worktree::ShellRunner.new`), `finisher:` (defaults to
# `Worktree.method(:finish)`), `status_checker:` (defaults to a `git status --porcelain`
# lambda), `gate:` (defaults to `Bridge.method(:code_gate_decision)`). Every seam exists so
# tests run with no real git, no real worktree removal, and no real bridge file outside a
# tmpdir.
#
# DOES NOT RUN A TEST SUITE, in any form. `verify-intent` owns test execution; one concern
# per script (spec D8).
module ExecWorktree
  module_function

  DISPOSITIONS = %w[delivered abandoned].freeze

  EXIT_OK = 0
  EXIT_USAGE = 1
  EXIT_PRECONDITION = 2
  EXIT_NOT_CLEAN = 3
  EXIT_UNRESOLVED = 4

  PROBE_FILENAME = "exec-worktree-precondition-probe"

  # The advisory line, verbatim (spec D7): printed whenever the order precondition
  # actually ran (delivered disposition, a code worktree present), on BOTH the pass and
  # the fail path, so no reader mistakes this script for the enforcement point.
  ADVISORY_LINE =
    "This precondition is a friendly early error, not the enforcement point. The hook " \
    "layer (scripts/lib/bridge.rb code_gate_decision, wired through " \
    "scripts/lib/edit_gates.rb) remains the actual gate. On a guided bridge this " \
    "precondition is advisory only."

  # --- seams (DI defaults) ----------------------------------------------------------

  # Real `git status --porcelain` against the code worktree, returning the same
  # [stdout, stderr, status] triple Open3.capture3 returns (status responds to
  # success?). A raised error (git missing, corrupt repo) is caught and reported as a
  # nil status, so the caller can fail closed the same way a failed exit status would.
  def default_status_checker
    lambda do |worktree_code|
      Open3.capture3("git", "-C", worktree_code, "status", "--porcelain")
    rescue StandardError => e
      [nil, e.message, nil]
    end
  end

  # --- pure helpers ------------------------------------------------------------------

  # Normalize either spelling of --home to the OS-HOME level (the PARENT of `.plastic`),
  # which is what `Worktree.finish`'s `home:` keyword wants
  # (`Worktree.home_from_store`, scripts/lib/worktree.rb:90). When the given path's
  # basename is literally `.plastic`, its dirname is used; otherwise the path is used
  # as given.
  def normalize_home(home)
    expanded = File.expand_path(home.to_s.sub(/\A~/, Dir.home))
    File.basename(expanded) == ".plastic" ? File.dirname(expanded) : expanded
  end

  # Session resolution order (mirrors scripts/end-intent:418-426, not
  # scripts/start-intent's no-fallback order): explicit --session, else
  # CLAUDE_CODE_SESSION_ID (passed in as env_session, never read from ENV here), else
  # the existing delivery.lock's own recorded owner_session when non-blank, else nil.
  # The lock-owner fallback is correct here: this is a teardown step on an intent this
  # session has been delivering.
  def resolve_session(explicit, env_session, intent_dir)
    return explicit.to_s.strip unless Bridge.blank?(explicit)
    return env_session.to_s.strip unless Bridge.blank?(env_session)
    lock = Lock.read(intent_dir)
    return nil unless lock
    owner = lock["owner_session"].to_s
    Bridge.blank?(owner) ? nil : owner
  end

  # --- result builders (mirror StartIntent's exit_code/stdout/stderr shape) --------

  def usage_result(message)
    { exit_code: EXIT_USAGE, stderr: ["exec-worktree: #{message}"], stdout: [] }
  end

  def deny_result(code, messages)
    { exit_code: code, stderr: Array(messages), stdout: [] }
  end

  def ok_result(messages)
    { exit_code: EXIT_OK, stderr: [], stdout: Array(messages) }
  end

  # --- messages ------------------------------------------------------------------------

  def no_session_message(intent_dir)
    "exec-worktree: a delivery lock exists at #{Lock.path(intent_dir)} but no session " \
      "identity could be resolved (--session, CLAUDE_CODE_SESSION_ID, and the lock's own " \
      "recorded owner are all blank); refusing rather than guessing."
  end

  def no_bridge_message(intent_dir, session, id)
    "exec-worktree: no bridge resolved for session #{session.inspect} and intent " \
      "#{id.inspect} (#{File.basename(intent_dir)}); any worktree this intent provisioned " \
      "was NOT removed. Run /plastic-doctor to check for an orphaned worktree."
  end

  def nothing_provisioned_message(intent_dir)
    "exec-worktree: #{File.basename(intent_dir)} has no code worktree recorded on its " \
      "bridge (precondition: skipped, no code worktree); nothing was provisioned, nothing " \
      "to finish."
  end

  def status_check_failed_message(worktree_code, err)
    "exec-worktree: could not inspect the code worktree at #{worktree_code} (git status " \
      "failed: #{err.to_s.strip}); refusing to remove it, because removal would " \
      "force-discard any uncommitted work."
  end

  def dirty_worktree_message(worktree_code)
    "exec-worktree: code worktree #{worktree_code} has uncommitted changes; refusing to " \
      "remove it. Commit or stash the changes, or run end-intent " \
      "--discard-worktree-changes to force the close deliberately (that flag belongs to " \
      "end-intent, not this script)."
  end

  def finish_incomplete_message(worktree_code)
    "exec-worktree: the code worktree at #{worktree_code} is still present after finish; " \
      "teardown did not complete. Run /plastic-doctor to check the worktree/lock status."
  end

  # --- report (printed only when the run reaches a normal finish) ------------------

  def build_report(intent_dir:, disposition:, precondition_status:, worktree_code:, branch:, removed:)
    merge_line = disposition == "delivered" ? "merged into #{branch}" : "not attempted (abandoned)"
    [
      "exec-worktree: #{File.basename(intent_dir)}",
      "  disposition: #{disposition}",
      "  precondition: #{precondition_status}",
      "  worktree:     #{worktree_code}",
      "  branch:       #{branch}",
      "  merge:        #{merge_line}",
      "  cleanup:      #{removed ? 'removed' : 'still present'}",
    ].join("\n")
  end

  # --- entry point ---------------------------------------------------------------------

  def run(store:, id:, home:, disposition:, session:, env_session:,
          runner: Worktree::ShellRunner.new,
          finisher: Worktree.method(:finish),
          status_checker: default_status_checker,
          gate: Bridge.method(:code_gate_decision))
    return usage_result("--store is required") if Bridge.blank?(store)
    return usage_result("--id is required") if Bridge.blank?(id)
    return usage_result("--home is required") if Bridge.blank?(home)
    return usage_result("--disposition is required") if Bridge.blank?(disposition)
    unless DISPOSITIONS.include?(disposition)
      return usage_result("--disposition must be one of #{DISPOSITIONS.join('|')} (got #{disposition.inspect})")
    end

    store_abs = ScaffoldIntent.expand(store)
    return usage_result("store dir does not exist: #{store_abs}") unless Dir.exist?(store_abs)

    intent_dir, resolve_err = ScaffoldIntent.resolve_intent_dir(store_abs, id)
    return usage_result(resolve_err) if intent_dir.nil?

    normalized_home = normalize_home(home)

    # Step 0: session resolution + pre-flight refusal (D3-mirroring; see resolve_session).
    key_session = resolve_session(session, env_session, intent_dir)
    if Bridge.blank?(key_session) && File.exist?(Lock.path(intent_dir))
      return deny_result(EXIT_UNRESOLVED, no_session_message(intent_dir))
    end

    bridge_data = Bridge.blank?(key_session) ? nil : Bridge.read(key_session, intent_id: id)
    return ok_result(no_bridge_message(intent_dir, key_session, id)) if bridge_data.nil?

    worktree_code = bridge_data.dig("worktree", "code")
    return ok_result(nothing_provisioned_message(intent_dir)) if Bridge.blank?(worktree_code)

    branch = bridge_data.dig("worktree", "code_branch")

    precondition_ran = false
    precondition_status = "not run (abandoned)"

    if disposition == "delivered"
      precondition_ran = true

      # Step 1: the order precondition. Call Bridge.code_gate_decision AS-IS (never
      # relaxed, never duplicated). See the module doc's "order-precondition trap".
      probe_path = File.join(worktree_code, PROBE_FILENAME)
      reason = gate.call(bridge_data, probe_path, home: normalized_home)
      if reason
        return deny_result(EXIT_PRECONDITION, [reason, ADVISORY_LINE])
      end
      precondition_status = bridge_data.dig("build", "auto") == true ? "passed" : "advisory (guided bridge)"

      # Step 2: the dirty-worktree guard, delivered only. Fail CLOSED when the check
      # itself fails or raises: removal force-removes on a plain failure, which would
      # destroy uncommitted work an inconclusive check could not rule out.
      out, err, status = status_checker.call(worktree_code)
      if status.nil? || !status.respond_to?(:success?) || !status.success?
        return deny_result(EXIT_NOT_CLEAN, status_check_failed_message(worktree_code, err))
      elsif !out.to_s.strip.empty?
        return deny_result(EXIT_NOT_CLEAN, dirty_worktree_message(worktree_code))
      end
    end

    # Step 3: finish. Worktree.finish is fail-open and never raises, so failure is
    # detected afterward, for a delivered disposition only, by checking whether the
    # worktree directory still exists on disk (release removes it on success).
    finisher.call(bridge_data, home: normalized_home, runner: runner,
                  merge: disposition == "delivered")

    removed = !Dir.exist?(worktree_code)
    if disposition == "delivered" && !removed
      return deny_result(EXIT_NOT_CLEAN, finish_incomplete_message(worktree_code))
    end

    report = build_report(intent_dir: intent_dir, disposition: disposition,
                          precondition_status: precondition_status,
                          worktree_code: worktree_code, branch: branch, removed: removed)

    stdout = precondition_ran ? [ADVISORY_LINE, report] : [report]
    ok_result(stdout)
  end
end
