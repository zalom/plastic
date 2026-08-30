# encoding: UTF-8
# frozen_string_literal: true

require "open3"
require_relative "bridge"
require_relative "arm"
require_relative "lock"
require_relative "worktree"
require_relative "scaffold_intent"

# ExecWorktree - all logic for `scripts/exec-worktree` (intent 213, group 2). Finish an
# intent's code worktree: the dirty-worktree guard, then `Worktree.finish` (delivered merges
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
# Pure and dependency-injected: never calls `exit` or `abort`, never reads `ARGV` directly.
# Seams: `runner:` (git, defaults to `Worktree::ShellRunner.new`; also used AFTER finish, for
# a delivered disposition, to verify from committed git state that the merge actually landed,
# since `Worktree.finish`'s return value is discarded by design and its underlying merge is
# fail-open, see the merge-verification note below), `finisher:` (defaults to
# `Worktree.method(:finish)`), `status_checker:` (defaults to a `git status --porcelain`
# lambda). Every seam exists so
# tests run with no real git, no real worktree removal, and no real bridge file outside a
# tmpdir.
#
# MERGE VERIFICATION (delivered disposition only). `Worktree.merge_branch` is deliberately
# fail-open: on a conflict it runs `git merge --abort`, warns, and returns false, and
# `Worktree.finish` still removes the worktree afterward regardless. So a conflicted merge
# and a clean merge look identical from this module's point of view unless it checks. This
# module never trusts the discarded return value; it asks git directly, AFTER finish, whether
# the intent's code branch is now an ancestor of the repo's current HEAD
# (`merged_into_current_branch?` below). `repo` and `branch` are captured BEFORE the finisher
# runs, because finish deletes the bridge's `worktree` block.
#
# DOES NOT RUN A TEST SUITE, in any form. `verify-intent` owns test execution; one concern
# per script (spec D8).
module ExecWorktree
  module_function

  DISPOSITIONS = %w[delivered abandoned].freeze

  EXIT_OK = 0
  EXIT_USAGE = 1
  # exit 2 was the order precondition; retired in 2.0 (intent 302) and never reused
  EXIT_NOT_CLEAN = 3
  EXIT_UNRESOLVED = 4

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

  # The repo a code worktree belongs to, derived from its own path rather than re-resolved
  # through projects.yml: `Worktree.paths` always builds a code worktree at
  # `<repo>/.claude/worktrees/<name>` (scripts/lib/worktree.rb:75), so walking up three
  # directories recovers `<repo>` deterministically, with no I/O and no git.
  def repo_from_worktree_code(worktree_code)
    return nil if Bridge.blank?(worktree_code)
    File.dirname(File.dirname(File.dirname(worktree_code.to_s)))
  end

  # BLOCKING 1/2 fix: read committed git state instead of trusting Worktree.finish's
  # discarded return value. True iff `branch` is now an ancestor of `repo`'s current HEAD,
  # i.e. the merge actually landed. Fails CLOSED (not merged) on a blank repo/branch or a
  # raising runner, so an inconclusive check is never reported as a success.
  def merged_into_current_branch?(runner, repo:, branch:)
    return false if Bridge.blank?(repo) || Bridge.blank?(branch)
    runner.run("-C", repo, "merge-base", "--is-ancestor", branch, "HEAD").success?
  rescue StandardError
    false
  end

  # Session resolution order (mirrors scripts/end-intent:418-426): explicit --session, else
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

  # --- result builders (the exit_code/stdout/stderr shape the thin CLIs share) --------

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

  def nothing_provisioned_message(intent_dir)
    "exec-worktree: #{File.basename(intent_dir)} has no code worktree on disk " \
      "(projects.yml and the intent id resolve none); nothing was provisioned, nothing " \
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

  def merge_not_landed_message(branch)
    "exec-worktree: the merge did not land: #{branch} is not an ancestor of the repo's " \
      "current HEAD after finish; the work is still on #{branch} and was not merged, so " \
      "nothing is lost. Resolve the conflict, then merge #{branch} by hand, or re-run " \
      "finish once it can merge cleanly."
  end

  # --- report (printed only when the run reaches a normal finish) ------------------

  def build_report(intent_dir:, disposition:, worktree_code:, branch:,
                   target_branch:, removed:)
    # This is only ever reached for "delivered" AFTER `run` has already confirmed, by
    # reading committed git state (merged_into_current_branch?), that `branch` IS an
    # ancestor of the repo's current HEAD; a merge that did not land returns from `run`
    # before build_report is ever called (BLOCKING 1). So this never asserts an outcome
    # that was not read (BLOCKING 2), and `target_branch` (the repo's OWN current branch,
    # the real integration target) replaces the old, wrong use of `branch` (the SOURCE
    # branch) in this line.
    merge_line =
      if disposition != "delivered"
        "not attempted (abandoned)"
      elsif Bridge.blank?(target_branch)
        "merged (integration target branch could not be resolved)"
      else
        "merged into #{target_branch}"
      end
    [
      "exec-worktree: #{File.basename(intent_dir)}",
      "  disposition: #{disposition}",
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
          status_checker: default_status_checker)
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

    bridge_data = Arm.bridge_hash(intent_dir: intent_dir, home: normalized_home)
    worktree_code = bridge_data.dig("worktree", "code")
    return ok_result(nothing_provisioned_message(intent_dir)) if Bridge.blank?(worktree_code)

    branch = bridge_data.dig("worktree", "code_branch")
    # Captured now, before `finisher.call` below (Worktree.finish) deletes the bridge's
    # `worktree` block, so the post-finish merge verification (BLOCKING 1/2) still has
    # both `repo` and `branch` to work with.
    repo = repo_from_worktree_code(worktree_code)

    if disposition == "delivered"
      # Step 1: the dirty-worktree guard, delivered only. Fail CLOSED when the check
      # itself fails or raises: removal force-removes on a plain failure, which would
      # destroy uncommitted work an inconclusive check could not rule out.
      out, err, status = status_checker.call(worktree_code)
      if status.nil? || !status.respond_to?(:success?) || !status.success?
        return deny_result(EXIT_NOT_CLEAN, status_check_failed_message(worktree_code, err))
      elsif !out.to_s.strip.empty?
        return deny_result(EXIT_NOT_CLEAN, dirty_worktree_message(worktree_code))
      end
    end

    # Step 2: finish. Worktree.finish is fail-open and never raises: on a merge conflict it
    # aborts the merge, warns, and STILL removes the worktree (Worktree.merge_branch,
    # scripts/lib/worktree.rb:246-258). So a failed merge is invisible both in this call's
    # return value (discarded, as before) and in whether the worktree directory still
    # exists (gone either way). Detected afterward in two steps: first, for a delivered
    # disposition only, whether the worktree directory still exists on disk (teardown
    # incomplete); second, for a delivered disposition only, whether the branch actually
    # merged (BLOCKING 1/2, see merged_into_current_branch? above).
    finisher.call(bridge_data, home: normalized_home, runner: runner,
                  merge: disposition == "delivered")

    removed = !Dir.exist?(worktree_code)
    if disposition == "delivered" && !removed
      return deny_result(EXIT_NOT_CLEAN, finish_incomplete_message(worktree_code))
    end

    target_branch = nil
    if disposition == "delivered"
      unless merged_into_current_branch?(runner, repo: repo, branch: branch)
        return deny_result(EXIT_NOT_CLEAN, merge_not_landed_message(branch))
      end
      target_branch = Worktree.current_branch(runner, repo: repo)
    end

    report = build_report(intent_dir: intent_dir, disposition: disposition,
                          worktree_code: worktree_code, branch: branch,
                          target_branch: target_branch, removed: removed)

    ok_result([report])
  end
end
