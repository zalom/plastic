# encoding: UTF-8
# frozen_string_literal: true

require_relative "arm"
require_relative "lock"
require_relative "worktree"
require_relative "scaffold_intent"

# ExecWorktree - all logic for `scripts/exec-worktree` (intent 213, group 2; intent 390
# removed the git it used to run). Plastic runs no version control command: this module
# never inspects, merges, or removes the code worktree an intent's delivery derived. It
# resolves the intent's worktree block and prints the three steps the agent or owner
# still has to run by hand: commit in the worktree, merge the branch into the base, and
# remove the worktree.
#
# Pure and dependency-injected: never calls `exit` or `abort`, never reads `ARGV` directly.
# No seam shells out; every path is computed from projects.yml and the intent id.
#
# DOES NOT RUN A TEST SUITE, in any form. `verify-intent` owns test execution; one concern
# per script (spec D8).
module ExecWorktree
  module_function

  DISPOSITIONS = %w[delivered abandoned].freeze

  EXIT_OK = 0
  EXIT_USAGE = 1
  EXIT_UNRESOLVED = 4

  # --- pure helpers ------------------------------------------------------------------

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # Normalize either spelling of --home to the OS-HOME level (the PARENT of `.plastic`).
  # When the given path's basename is literally `.plastic`, its dirname is used;
  # otherwise the path is used as given.
  def normalize_home(home)
    expanded = File.expand_path(home.to_s.sub(/\A~/, Dir.home))
    File.basename(expanded) == ".plastic" ? File.dirname(expanded) : expanded
  end

  # The repo a code worktree belongs to, derived from its own path rather than re-resolved
  # through projects.yml: `Worktree.paths` always builds a code worktree at
  # `<repo>/.claude/worktrees/<name>` (scripts/lib/worktree.rb), so walking up three
  # directories recovers `<repo>` deterministically, with no I/O and no git.
  def repo_from_worktree_code(worktree_code)
    return nil if blank?(worktree_code)
    File.dirname(File.dirname(File.dirname(worktree_code.to_s)))
  end

  # Session resolution order (mirrors scripts/end-intent): explicit --session, else
  # CLAUDE_CODE_SESSION_ID (passed in as env_session, never read from ENV here), else
  # the existing delivery.lock's own recorded owner_session when non-blank, else nil.
  # The lock-owner fallback is correct here: this is a teardown step on an intent this
  # session has been delivering.
  def resolve_session(explicit, env_session, intent_dir)
    return explicit.to_s.strip unless blank?(explicit)
    return env_session.to_s.strip unless blank?(env_session)
    lock = Lock.read(intent_dir)
    return nil unless lock
    owner = lock["owner_session"].to_s
    blank?(owner) ? nil : owner
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

  # --- report (the printed instruction; Plastic runs none of these itself) -----------

  def build_report(intent_dir:, disposition:, worktree_code:, branch:, repo:, base_branch:)
    lines = [
      "exec-worktree: #{File.basename(intent_dir)}",
      "  disposition: #{disposition}",
      "  worktree:     #{worktree_code}",
      "  branch:       #{branch}",
      "next: commit any remaining changes in #{worktree_code}",
    ]
    if disposition == "delivered"
      lines << "  then: git -C #{repo} merge #{branch}  (into #{base_branch}, from a checkout on #{base_branch})"
    end
    lines << "  then: git -C #{repo} worktree remove #{worktree_code}"
    lines.join("\n")
  end

  # --- entry point ---------------------------------------------------------------------

  def run(store:, id:, home:, disposition:, session:, env_session:)
    return usage_result("--store is required") if blank?(store)
    return usage_result("--id is required") if blank?(id)
    return usage_result("--home is required") if blank?(home)
    return usage_result("--disposition is required") if blank?(disposition)
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
    if blank?(key_session) && File.exist?(Lock.path(intent_dir))
      return deny_result(EXIT_UNRESOLVED, no_session_message(intent_dir))
    end

    delivery = Arm.delivery(intent_dir: intent_dir, home: normalized_home)
    worktree_code = delivery.dig("worktree", "code")
    return ok_result(nothing_provisioned_message(intent_dir)) if blank?(worktree_code)

    branch = delivery.dig("worktree", "code_branch")
    repo = repo_from_worktree_code(worktree_code)
    base_branch = ScaffoldIntent.detect_base_branch(repo, home: normalized_home)

    report = build_report(intent_dir: intent_dir, disposition: disposition,
                          worktree_code: worktree_code, branch: branch, repo: repo,
                          base_branch: base_branch)

    ok_result([report])
  end
end
