# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "yaml"
require "socket"
require "time"
require_relative "lock"

# Worktree -- Plastic-supplied git worktree isolation and the delivery lock
# (intent 73c / 73c1).
#
# The harness `EnterWorktree` tool assumes cwd IS the repo root, which is false
# for Plastic (cwd is often the parent of the repo subdir). When the mismatch
# occurs the tool silently degrades to a plain feature branch on the shared
# checkout, so parallel intent deliveries are NOT isolated. This module makes
# isolation deterministic and cwd-independent: Plastic resolves the repo from
# projects.yml and runs `git -C <repo> worktree add`, so the cwd-not-root bug
# dies by construction (decision D6).
#
# Two worktrees per project intent, both named `{id}--{slug}` (decision D2):
#   code  worktree  <repo>/.claude/worktrees/{id}--{slug}  branch plastic/{id}--{slug}
#   store worktree  <plastic_home>/.worktrees/{id}--{slug} branch plastic-store/{id}--{slug}
#
# The durable delivery.lock file in the intent dir is the single-owner
# delivery lock (intent 108): session-keyed, lease-based, explicit takeover.
#
# Pure and dependency-injected: every git call goes through an injected
# `ShellRunner`, so unit tests are hermetic (no real git; inject a fake runner).
# No eval, no global/ENV config injection.
module Worktree
  module_function

  # --- ShellRunner (DI seam) -------------------------------------------------

  # The default runner shells out to real `git`. Tests inject a fake with the
  # same `run(*args)` contract so no real git runs in unit tests.
  class ShellRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def run(*args)
      require "open3"
      out, err, status = Open3.capture3("git", *args.map(&:to_s))
      Result.new(status.exitstatus.to_i, out, err)
    end
  end

  # --- pure helpers ----------------------------------------------------------

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # The `{id}--{slug}` identity shared by both worktrees and both branches.
  def dir_name(intent_id, intent_slug)
    "#{intent_id}--#{intent_slug}"
  end

  # Pure, deterministic. Returns the four paths/branches. No git calls.
  # `repo_path` is resolved from projects.yml when nil; when it cannot be
  # resolved the code worktree path/branch are nil (a global-store-only intent).
  def paths(slug:, intent_id:, intent_slug:, home: Dir.home, repo_path: nil)
    name = dir_name(intent_id, intent_slug)
    repo = repo_path || repo_for(slug, home: home)
    plastic_home = File.expand_path(File.join(home, ".plastic"))

    code_path = repo ? File.join(File.expand_path(repo), ".claude", "worktrees", name) : nil
    store_path = File.join(plastic_home, ".worktrees", name)

    {
      "code" => code_path,
      "code_branch" => code_path ? "plastic/#{name}" : nil,
      "store" => store_path,
      "store_branch" => "plastic-store/#{name}",
    }
  end

  # Absolute repo path for a project slug from `~/.plastic/projects.yml`, or nil.
  # Reuses the qmd_sync safe-loader pattern: any failure yields nil.
  def repo_for(slug, home: Dir.home)
    return nil if blank?(slug)
    projects = load_projects(home)
    info = projects[slug.to_s]
    path = info.is_a?(Hash) ? info["path"] : nil
    return nil if blank?(path)
    File.expand_path(path)
  end

  # --- provisioning ----------------------------------------------------------

  # Resolve the slug from the bridge's intent.store, create code + store
  # worktrees (idempotent: reuse an existing worktree path, do not error), write
  # the `worktree` block plus `provisioned: true` onto bridge_data, return it.
  #
  # Fails open with a stderr log when the repo is non-git or unresolvable:
  # sets `provisioned: false` and leaves `code: null`. All git ops use
  # `git -C <resolved path>` -- never cwd (decision D6).
  def provision(bridge_data, home: Dir.home, runner: ShellRunner.new)
    return bridge_data unless bridge_data.is_a?(Hash)
    intent = bridge_data["intent"] || {}
    intent_id = intent["id"].to_s
    store = intent["store"].to_s
    intent_slug = slug_from_dir(intent["dir"]) || slug_from_dir(store)

    slug = slug_for_store(store, home: home)
    p = paths(slug: slug, intent_id: intent_id, intent_slug: intent_slug, home: home)

    block = {
      "code" => nil,
      "code_branch" => nil,
      "store" => p["store"],
      "store_branch" => p["store_branch"],
      "provisioned" => false,
    }

    plastic_home = File.expand_path(File.join(home, ".plastic"))

    # Gitignore safety (intent 73c3): the store worktrees live under the store git
    # repo, so without ignoring `.worktrees/` a `git add -A` sweeps their gitlinks
    # into the store commit. Ensure both ignore entries before any worktree add.
    ensure_gitignored(plastic_home, ".worktrees/", runner: runner)

    # Store worktree: created against the plastic home git repo. Fail-open if the
    # store repo is not a git repo (a fresh global store may be ungit'd).
    store_ok = add_worktree(runner, repo: plastic_home,
                            worktree: p["store"], branch: p["store_branch"],
                            label: "store")

    # Code worktree: MANDATORY for project intents. Fail-open when the repo is
    # unresolvable or non-git -- that is the global-store-only / non-git case.
    repo = repo_for(slug, home: home)
    code_ok = false
    if repo && git_repo?(runner, repo)
      ensure_gitignored(repo, ".claude/worktrees/", runner: runner)
      code_ok = add_worktree(runner, repo: repo,
                             worktree: p["code"], branch: p["code_branch"],
                             label: "code")
      if code_ok
        block["code"] = p["code"]
        block["code_branch"] = p["code_branch"]
      end
    else
      warn "plastic: worktree provision fail-open -- repo for slug #{slug.inspect} " \
           "is unresolvable or not a git repo; code worktree skipped"
    end

    block["store"] = store_ok ? p["store"] : nil
    block["store_branch"] = store_ok ? p["store_branch"] : nil

    # provisioned is true only when the MANDATORY code worktree exists. The gate
    # fails open on provisioned: false (non-git / global-only).
    block["provisioned"] = code_ok

    bridge_data["worktree"] = block
    bridge_data
  end

  # Remove both worktrees (then `git worktree prune`), clear the worktree block.
  # No-op when nothing was provisioned. CLEANUP (73c3) layers the merge-vs-remove
  # policy on top via `finish`; this is the plain remove. Pass `remove: false` to
  # clear the block WITHOUT touching git (so `finish` can merge first, then call
  # release to drop the worktrees once the code branch is integrated).
  def release(bridge_data, home: Dir.home, runner: ShellRunner.new, remove: true)
    return bridge_data unless bridge_data.is_a?(Hash)
    block = bridge_data["worktree"]
    return bridge_data unless block.is_a?(Hash)

    if remove
      plastic_home = File.expand_path(File.join(home, ".plastic"))
      slug = slug_for_store(bridge_data.dig("intent", "store").to_s, home: home)
      repo = repo_for(slug, home: home)

      remove_worktree(runner, repo: repo, worktree: block["code"]) if repo && block["code"]
      remove_worktree(runner, repo: plastic_home, worktree: block["store"]) if block["store"]

      prune(runner, repo: repo) if repo
      prune(runner, repo: plastic_home)
    end

    bridge_data.delete("worktree")
    bridge_data
  end

  # --- cleanup policy (merge-vs-remove) -------------------------------------

  # Finish an intent's delivery by tearing down its worktrees, optionally merging
  # the code branch back first (intent 73c3). The merge-vs-remove decision is the
  # one piece of policy on top of the plain `release`:
  #
  #   merge: true  -> the releasing path. Merge the intent's code branch
  #                   (`plastic/{id}--{slug}`) into the repo's default branch
  #                   BEFORE removing the worktrees, so the work is integrated and
  #                   not lost when the worktree disappears. Then `release`.
  #   merge: false -> the disarm / abandon path. Just `release` (plain remove);
  #                   the branch survives and can be reclaimed.
  #
  # Fail-open and idempotent throughout: a missing block, missing branch, or any
  # git failure never raises and never blocks teardown. All git ops use
  # `git -C <path>`, never cwd (decision D6). No-op when nothing was provisioned.
  def finish(bridge_data, home: Dir.home, runner: ShellRunner.new, merge: false)
    return bridge_data unless bridge_data.is_a?(Hash)
    block = bridge_data["worktree"]
    return bridge_data unless block.is_a?(Hash)

    if merge
      slug = slug_for_store(bridge_data.dig("intent", "store").to_s, home: home)
      repo = repo_for(slug, home: home)
      branch = block["code_branch"]
      merge_branch(runner, repo: repo, branch: branch) if repo && !blank?(branch)
    end

    release(bridge_data, home: home, runner: runner, remove: true)
  end

  # Merge `branch` into the repo's default branch from the main checkout. The
  # worktree the branch is checked out in stays put; we merge in the repo dir
  # itself (its own current branch is the integration target). Idempotent: a
  # no-op merge ("Already up to date") still succeeds. Fail-open: a conflicting
  # or otherwise failing merge is aborted and logged, never raised, so teardown
  # still proceeds (CLEANUP must not strand a worktree).
  def merge_branch(runner, repo:, branch:)
    return false if blank?(repo) || blank?(branch)
    target = current_branch(runner, repo: repo)
    return false if blank?(target) || target == branch

    res = runner.run("-C", repo, "merge", "--no-ff", "--no-edit", branch)
    return true if res.success?

    # Leave the integration branch clean: abort a half-applied/conflicted merge.
    runner.run("-C", repo, "merge", "--abort")
    warn "plastic: worktree finish could not merge #{branch.inspect} into " \
         "#{target.inspect}: #{res.stderr.to_s.strip}; removing worktree without merge"
    false
  end

  # The repo's current branch (the integration target), or nil when detached /
  # unresolvable.
  def current_branch(runner, repo:)
    return nil if blank?(repo)
    res = runner.run("-C", repo, "rev-parse", "--abbrev-ref", "HEAD")
    return nil unless res.success?
    name = res.stdout.to_s.strip
    (name.empty? || name == "HEAD") ? nil : name
  end

  # --- gitignore safety ------------------------------------------------------

  # Ensure `entry` is present in `<repo>/.gitignore`, appending it once if absent
  # (idempotent). Without this, the store worktrees that live UNDER the store git
  # repo (~/.plastic/.worktrees/) get swept into the store commit by a `git add
  # -A`, polluting the index with worktree gitlinks (observed during 73c1
  # integration). Provisioning and cleanup both call this so the repos' indexes
  # stay clean. Best-effort and non-raising: any failure is logged, never raised.
  def ensure_gitignored(repo, entry, runner: ShellRunner.new)
    return false if blank?(repo) || blank?(entry) || !Dir.exist?(repo)
    gitignore = File.join(File.expand_path(repo), ".gitignore")
    want = entry.to_s.strip

    existing = File.exist?(gitignore) ? File.read(gitignore) : ""
    present = existing.each_line.any? { |line| line.strip == want }
    return true if present

    File.open(gitignore, "a") do |io|
      io.write("\n") unless existing.empty? || existing.end_with?("\n")
      io.write("#{want}\n")
    end
    true
  rescue StandardError => e
    warn "plastic: ensure_gitignored(#{entry.inspect}) failed for #{repo.inspect}: #{e.message}"
    false
  end

  # --- lock ------------------------------------------------------------------

  # True iff ANOTHER session's delivery.lock is FRESH on this intent's dir
  # (intent 108, D2): the durable lock file decides; /tmp bridges are not
  # consulted and no pid is probed. current_session being the owner or a
  # delegate does not count as "other". A stale lock does not hold (explicit
  # takeover reclaims it).
  def lock_held_by_other?(intent_id:, store:, current_session:, home: Dir.home,
                          ttl: Lock::TTL_SECONDS, now: Time.now)
    return false if blank?(store)
    dir = Dir.glob(File.join(File.expand_path(store), "#{intent_id}--*")).first
    return false unless dir
    data = Lock.read(dir)
    return false unless data
    return false if Lock.authorized?(data, current_session)
    Lock.fresh?(dir, ttl: ttl, now: now)
  rescue StandardError
    false
  end

  # --- git operations (all use -C, never cwd) --------------------------------

  # Idempotent worktree add. If `worktree` already exists on disk, treat as
  # reuse (success, no git call). Otherwise `git -C <repo> worktree add <wt>
  # -b <branch>`; if the branch already exists, retry without -b (reattach).
  def add_worktree(runner, repo:, worktree:, branch:, label:)
    return false if blank?(repo) || blank?(worktree)
    return true if Dir.exist?(worktree) # idempotent reuse

    res = runner.run("-C", repo, "worktree", "add", worktree, "-b", branch)
    return true if res.success?

    # Branch may already exist (a prior provision that was pruned but kept the
    # branch). Retry attaching the existing branch.
    res2 = runner.run("-C", repo, "worktree", "add", worktree, branch)
    return true if res2.success?

    warn "plastic: worktree add (#{label}) failed: #{res.stderr.to_s.strip}"
    false
  end

  def remove_worktree(runner, repo:, worktree:)
    return false if blank?(repo) || blank?(worktree)
    res = runner.run("-C", repo, "worktree", "remove", worktree)
    unless res.success?
      # Force-remove tolerates dirty/locked worktrees; CLEANUP owns merge policy.
      res = runner.run("-C", repo, "worktree", "remove", "--force", worktree)
    end
    res.success?
  end

  def prune(runner, repo:)
    return false if blank?(repo)
    runner.run("-C", repo, "worktree", "prune").success?
  end

  # True iff `repo` is a git work tree (idempotent, no mutation).
  def git_repo?(runner, repo)
    return false if blank?(repo) || !Dir.exist?(repo)
    res = runner.run("-C", repo, "rev-parse", "--is-inside-work-tree")
    res.success? && res.stdout.to_s.strip == "true"
  end

  # --- internals (projects.yml resolution, mirrors qmd_sync) -----------------

  def load_projects(home)
    path = File.join(File.expand_path(home), ".plastic", "projects.yml")
    return {} unless File.exist?(path)
    data = begin
      YAML.safe_load(File.read(path)) || {}
    rescue StandardError
      {}
    end
    projects = data.is_a?(Hash) ? data["projects"] : nil
    projects.is_a?(Hash) ? projects : {}
  end

  # Resolve a project slug from a store directory. A project's tactical store
  # lives at <plastic_home>/projects/<slug>/store; the global store yields nil
  # (no project repo). Mirrors qmd_sync's slug_for_store fallback.
  def slug_for_store(store_dir, home: Dir.home)
    return nil if blank?(store_dir)
    plastic_home = File.expand_path(File.join(home, ".plastic"))
    store_dir = File.expand_path(store_dir)
    return nil if store_dir == File.join(plastic_home, "store")

    parts = store_dir.split(File::SEPARATOR)
    idx = parts.rindex("projects")
    return parts[idx + 1] if idx && parts[idx + 1] && parts[idx + 2] == "store"
    nil
  end

  # Best-effort slug for the worktree dir-name from an intent dir/store path:
  # the basename `{id}--{slug}` -> the `{slug}` portion (split on the first
  # `--`). Used only for naming.
  def slug_from_dir(dir)
    return nil if blank?(dir)
    base = File.basename(dir.to_s)
    idx = base.index("--")
    return nil unless idx
    base[(idx + 2)..]
  end

end
