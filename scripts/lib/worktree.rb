# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "yaml"
require "socket"
require "time"

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
# The bridge file doubles as the delivery lock (decision D3): single-owner,
# stale-lock reclaim via pid liveness.
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
  # No-op when nothing was provisioned. CLEANUP (73c3) owns the merge-vs-remove
  # policy; this is the plain remove.
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

  # --- lock ------------------------------------------------------------------

  # pid liveness: signal 0 probes without sending. Any error (no such process,
  # not ours) means not live.
  def session_live?(pid)
    n = Integer(pid) rescue nil
    return false if n.nil? || n <= 0
    Process.kill(0, n)
    true
  rescue StandardError
    false
  end

  # True iff ANOTHER bridge for this intent has a LIVE owner pid that is not
  # current_session. Scans /tmp/plastic-*.json (or `tmp`). The current session's
  # own bridge never counts as "other". A dead owner does not hold the lock
  # (stale-lock reclaim).
  def lock_held_by_other?(intent_id:, store:, current_session:, home: Dir.home, tmp: nil)
    tmp ||= default_tmp
    id = intent_id.to_s
    st = File.expand_path(store.to_s) unless blank?(store)

    Dir.glob(File.join(tmp, "plastic-*.json")).each do |f|
      next if f.end_with?(".tmp")
      data = (JSON.parse(File.read(f)) rescue nil)
      next unless data.is_a?(Hash)

      intent = data["intent"] || {}
      next unless intent["id"].to_s == id
      unless st.nil?
        bstore = intent["store"].to_s
        next unless bstore.empty? || File.expand_path(bstore) == st
      end

      session = data["session"].to_s
      next if !blank?(current_session) && session == current_session.to_s

      lock = data["lock"] || {}
      owner_pid = lock["pid"]
      return true if session_live?(owner_pid)
    end
    false
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

  def default_tmp
    t = ENV["PLASTIC_TMP"]
    (t.nil? || t.strip.empty?) ? "/tmp" : t
  end
end
