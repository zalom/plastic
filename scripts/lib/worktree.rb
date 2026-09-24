# encoding: UTF-8
# frozen_string_literal: true

require_relative "store_layout"
require "json"
require "yaml"
require "socket"
require "time"
require_relative "lock"

# Worktree -- the expected code worktree path and the delivery lock
# (intent 73c / 73c1; provisioning removed by intent 390).
#
# Plastic runs no version control command (owner ruling 2026-09-24, intent
# 390). It computes the deterministic path and branch a project intent's code
# worktree would have (<repo>/.claude/worktrees/{id}--{slug}, branch
# plastic/{id}--{slug}) and prints them (see Arm.worktree_block and
# `plastic auto take`'s screen); the agent that receives the instruction
# creates the worktree itself, e.g. `git -C <repo> worktree add <path> -b
# <branch>`, and removes/merges it itself too. `release`, `finish`, and
# `merge_branch` (the old teardown/merge git calls) are gone; `Arm.disarm`
# now only clears the lock and prints the removal instruction.
#
# One worktree per project intent (decision D2, retired to a single worktree by
# intent 178). Store-write safety for lifecycle-doc writes comes from intent
# 197's branch-from-main plus scoped-commit mechanism instead of a second,
# dedicated worktree (see PLASTIC.md's worktree doctrine).
#
# The durable delivery.lock file in the intent dir is the single-owner
# delivery lock (intent 108): session-keyed, lease-based, explicit takeover.
#
# Pure and dependency-injected. No eval, no global/ENV config injection.
module Worktree
  module_function

  # --- pure helpers ----------------------------------------------------------

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # The `{id}--{slug}` identity shared by both worktrees and both branches.
  def dir_name(intent_id, intent_slug)
    "#{intent_id}--#{intent_slug}"
  end

  # Pure, deterministic. Returns the code worktree's path/branch. No git calls.
  # `repo_path` is resolved from projects.yml when nil; when it cannot be
  # resolved the code worktree path/branch are nil (a global-store-only intent).
  # Store-worktree provisioning was retired by intent 178: this used to also
  # return a `store`/`store_branch` pair for a second worktree under
  # `<plastic_home>/.worktrees/{id}--{slug}`; nothing provisions that anymore.
  def paths(slug:, intent_id:, intent_slug:, home: Dir.home, repo_path: nil)
    name = dir_name(intent_id, intent_slug)
    repo = repo_path || repo_for(slug, home: home)

    code_path = repo ? File.join(File.expand_path(repo), ".claude", "worktrees", name) : nil

    {
      "code" => code_path,
      "code_branch" => code_path ? "plastic/#{name}" : nil,
    }
  end

  # Derive the OS-HOME level (the PARENT of `.plastic`) from an intent store
  # path, anchored on the `.plastic` path segment (Defect 1, intent 169): a
  # store is always `<plastic_home>/store` or
  # `<plastic_home>/projects/<slug>/store`, and `<plastic_home>` is always the
  # `.plastic` dir. Returns nil when `store` is blank or carries no `.plastic`
  # segment, so callers fall back to their own `home:` default rather than
  # resolving anything. Pure: no `ENV[...]` read, no I/O.
  def home_from_store(store)
    return nil if blank?(store)
    parts = File.expand_path(store.to_s).split(File::SEPARATOR)
    idx = parts.rindex(".plastic")
    return nil unless idx
    parts[0...idx].join(File::SEPARATOR)
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

  # --- gitignore safety ------------------------------------------------------

  # Ensure `entry` is present in `<repo>/.gitignore`, appending it once if absent
  # (idempotent). Without this, the store worktrees that live UNDER the store git
  # repo (~/.plastic/.worktrees/) get swept into the store commit by a `git add
  # -A`, polluting the index with worktree gitlinks (observed during 73c1
  # integration). Provisioning and cleanup both call this so the repos' indexes
  # stay clean. Best-effort and non-raising: any failure is logged, never raised.
  def ensure_gitignored(repo, entry)
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
  # (intent 108, D2): the durable lock file decides alone, and no pid is
  # probed. current_session being the owner or a
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
    slug = Plastic::StoreLayout.locate(store_dir).last
    (slug == Plastic::StoreLayout::GLOBAL) ? nil : slug
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
