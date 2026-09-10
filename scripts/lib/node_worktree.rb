# encoding: UTF-8
# frozen_string_literal: true

require_relative "worktree"
require_relative "node_ledger"
require_relative "ready_set"
require_relative "savepoint"

# NodeWorktree (intent 340, G7, n3): a work node's own git worktree, cut from
# the intent branch tip, merged back into the intent branch (never `alpha`),
# and swept once its node is terminal. Verify, research and decision nodes
# never get one (327 spec, C4: a verify node writes no code, so it gets
# nowhere to write a diff).
#
# The node worktree's identity is `<repo>/.claude/worktrees/<id>--<slug>--<node>`
# on branch `plastic/<id>--<slug>--<node>` - one path segment deeper than the
# intent worktree Worktree already provisions. `repo` is derived from
# `context.worktree` alone (it is always `<repo>/.claude/worktrees/<id>--<slug>`,
# the shape Worktree.paths itself constructs), never re-resolved through
# projects.yml: any git worktree of a repo can run `git worktree add` for a
# sibling, so the intent worktree is a perfectly good `-C` handle for every
# git call this module makes.
#
# Deliberately does NOT reuse Worktree.merge_branch (it resolves its target
# as the REPO's own currently checked-out branch, which is `alpha` in the
# ordinary case - merging node work there would skip the intent branch
# entirely) or WorktreeSweep (it globs the store-worktree tree intent 178
# retired and derives a `plastic-store/` branch name; it can never see a node
# worktree). This module carries its own merge and its own reaper.
#
# Pure and dependency-injected: every git call goes through an injected
# `runner:` (default Worktree::ShellRunner), always `-C <path>`, never cwd.
module NodeWorktree
  module_function

  # Only a `work` node gets a worktree (matrix 3.4/3.5).
  WORKTREE_KINDS = %w[work].freeze

  # release(state:) removes the worktree for these terminal states (matrix
  # 3.8, 3.11); every other state (failed_verification, needs_decision, or
  # anything not yet terminal) keeps it (matrix 3.9, 3.10) - the safe-by-
  # default direction, since evidence you cannot see cannot be reviewed.
  REMOVE_ON_STATES = %w[done superseded abandoned].freeze

  # --- paths -----------------------------------------------------------------

  # {"repo"=>, "path"=>, "branch"=>}, all nil when `context.worktree` is
  # blank (a global-store-only intent, matrix 3.6 - there is no repo to
  # derive a node worktree path under). Pure: no git call, no filesystem read.
  def paths(context, node:)
    repo = repo_root(context)
    return { "repo" => nil, "path" => nil, "branch" => nil } if repo.nil?

    name = worktree_name(context, node)
    { "repo" => repo, "path" => File.join(repo, ".claude", "worktrees", name), "branch" => "plastic/#{name}" }
  end

  # --- provisioning ------------------------------------------------------------

  # provision(context, node:, kind:) -> {ok:, path:, branch:, provisioned:}.
  # A non-`work` kind gets no worktree (matrix 3.4/3.5). An unresolvable or
  # non-git repo fails open (matrix 3.6): ok stays true, provisioned is
  # false, nothing raises. An existing worktree at the target path is reused,
  # never re-erred on (matrix 3.3).
  def provision(context, node:, kind:, runner: Worktree::ShellRunner.new)
    return unprovisioned unless WORKTREE_KINDS.include?(kind.to_s)

    p = paths(context, node: node)
    repo, path, branch = p["repo"], p["path"], p["branch"]
    return unprovisioned if repo.nil? || !Worktree.git_repo?(runner, repo)
    return { ok: true, path: path, branch: branch, provisioned: true } if Dir.exist?(path)

    intent_branch = context.worktree_branch
    return unprovisioned if blank?(intent_branch)

    # Cut FROM the intent branch's own tip (matrix 3.2), never from whatever
    # the repo's main checkout happens to have checked out - the exact bug
    # Worktree.merge_branch has on the merge side, avoided here on the add
    # side by naming the start point explicitly.
    res = runner.run("-C", repo, "worktree", "add", path, "-b", branch, intent_branch)
    return { ok: true, path: path, branch: branch, provisioned: true } if res.success?

    # The branch may already exist (a prior provision whose worktree was
    # pruned but whose branch survived): retry attaching it.
    res2 = runner.run("-C", repo, "worktree", "add", path, branch)
    if res2.success?
      { ok: true, path: path, branch: branch, provisioned: true }
    else
      warn "runner: node worktree provision failed for #{node}: #{res2.stderr.to_s.strip}"
      unprovisioned
    end
  end

  # --- diffing -----------------------------------------------------------------

  # changed_paths(context, node:) -> the file paths that differ between the
  # intent branch and this node's branch, or [] when either branch or the
  # repo cannot be resolved, or when the diff is genuinely empty (matrix
  # 3.13/3.14 - the empty case is never distinguished from "cannot compute",
  # both read as "nothing to report").
  def changed_paths(context, node:, runner: Worktree::ShellRunner.new)
    p = paths(context, node: node)
    repo, branch = p["repo"], p["branch"]
    return [] if blank?(repo) || blank?(branch) || blank?(context.worktree_branch)

    res = runner.run("-C", repo, "diff", "--name-only", "#{context.worktree_branch}...#{branch}")
    return [] unless res.success?

    res.stdout.to_s.each_line.map(&:strip).reject(&:empty?)
  end

  # --- merging -----------------------------------------------------------------

  # merge(context, node:) -> {ok:, commit:, conflicted:, error:}. Merges the
  # node branch INTO the intent branch, IN the intent worktree (matrix 3.7) -
  # never Worktree.merge_branch, which targets the repo's own current branch.
  # Refuses outright (matrix 3.7a) when the intent worktree is not actually
  # checked out on the intent branch, rather than merging into whatever it
  # happens to have checked out. A conflicted merge is aborted and its
  # conflicted paths (from `--diff-filter=U`) are returned, not a bare
  # boolean (matrix 3.12/3.12a) - `step` needs the paths to route D8's
  # inside-vs-outside-files: decision.
  def merge(context, node:, runner: Worktree::ShellRunner.new)
    p = paths(context, node: node)
    branch = p["branch"]
    intent_worktree = context.worktree

    if blank?(intent_worktree) || blank?(branch)
      return { ok: false, commit: nil, conflicted: [], error: "no intent worktree or node branch to merge" }
    end

    current = Worktree.current_branch(runner, repo: intent_worktree)
    if current != context.worktree_branch
      return {
        ok: false, commit: nil, conflicted: [],
        error: "intent worktree is checked out on #{current.inspect}, not #{context.worktree_branch.inspect}",
      }
    end

    res = runner.run("-C", intent_worktree, "merge", "--no-ff", "--no-edit", branch)
    if res.success?
      sha = runner.run("-C", intent_worktree, "rev-parse", "HEAD").stdout.to_s.strip
      return { ok: true, commit: (sha.empty? ? nil : sha), conflicted: [], error: nil }
    end

    conflicted = runner.run("-C", intent_worktree, "diff", "--name-only", "--diff-filter=U")
                        .stdout.to_s.each_line.map(&:strip).reject(&:empty?)
    runner.run("-C", intent_worktree, "merge", "--abort")
    { ok: false, commit: nil, conflicted: conflicted, error: res.stderr.to_s.strip }
  end

  # --- release (post-merge / post-terminal cleanup) -----------------------------

  # release(context, node:, state:) -> {ok:, removed:}. Removes the worktree
  # only for REMOVE_ON_STATES (matrix 3.8, 3.11); every other state, and a
  # worktree that is already gone, is left alone (matrix 3.9, 3.10).
  def release(context, node:, state:, runner: Worktree::ShellRunner.new)
    p = paths(context, node: node)
    repo, path = p["repo"], p["path"]
    return { ok: true, removed: false } if blank?(path) || !Dir.exist?(path)
    return { ok: true, removed: false } unless REMOVE_ON_STATES.include?(state.to_s)

    ok = Worktree.remove_worktree(runner, repo: repo, worktree: path)
    Worktree.prune(runner, repo: repo) if ok
    { ok: ok, removed: ok }
  end

  # --- the reaper ----------------------------------------------------------------

  # reap(context) -> {removed: [{node:, dir:}], spared: [{node:, dir:, reason:}]}.
  # Scoped to THIS intent's own node worktrees only (matrix 3.18): globs
  # `<repo>/.claude/worktrees/<id>--<slug>--*`, which by construction never
  # matches the intent's own worktree (`<id>--<slug>`, no third segment) or
  # any other intent's. A candidate is removed only when its node resolves
  # terminal (matrix 3.17) AND its branch carries no commits the intent
  # branch does not already have (matrix 3.16) - any ambiguity (an
  # unresolvable branch) spares it, never removes it.
  def reap(context, runner: Worktree::ShellRunner.new)
    repo = repo_root(context)
    return { removed: [], spared: [] } if repo.nil?

    base = File.join(repo, ".claude", "worktrees")
    return { removed: [], spared: [] } unless Dir.exist?(base)

    prefix = "#{context.intent_id}--#{context.intent_slug}--"
    status_map = NodeLedger.status_from_content(savepoint_content(context.intent_dir))

    removed = []
    spared = []

    Dir.glob(File.join(base, "#{prefix}*")).select { |d| File.directory?(d) }.sort.each do |dir|
      node = File.basename(dir).sub(prefix, "")
      next unless node.match?(Savepoint::NODE_SUBJECT_RE)

      state = status_map.fetch(node, "planned")
      unless ReadySet::TERMINAL_STATES.include?(state)
        spared << { node: node, dir: dir, reason: "not terminal (#{state})" }
        next
      end

      branch = "plastic/#{prefix}#{node}"
      ahead = branch_ahead(runner, repo, context.worktree_branch, branch)
      if ahead.nil? || ahead.positive?
        spared << { node: node, dir: dir, reason: "branch has unmerged commits, or is unresolvable" }
        next
      end

      if Worktree.remove_worktree(runner, repo: repo, worktree: dir)
        removed << { node: node, dir: dir }
      else
        spared << { node: node, dir: dir, reason: "worktree remove failed" }
      end
    end

    Worktree.prune(runner, repo: repo) unless removed.empty?
    { removed: removed, spared: spared }
  end

  # --- internals -----------------------------------------------------------------

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
  private_class_method :blank?

  def worktree_name(context, node)
    "#{context.intent_id}--#{context.intent_slug}--#{node}"
  end
  private_class_method :worktree_name

  # `context.worktree` is always `<repo>/.claude/worktrees/<id>--<slug>`
  # (Worktree.paths' own shape); three levels up is the repo root. nil when
  # `context.worktree` itself is blank.
  def repo_root(context)
    wt = context&.worktree
    return nil if blank?(wt)

    File.dirname(File.dirname(File.dirname(File.expand_path(wt))))
  end
  private_class_method :repo_root

  def unprovisioned
    { ok: true, path: nil, branch: nil, provisioned: false }
  end
  private_class_method :unprovisioned

  def savepoint_content(intent_dir)
    path = File.join(intent_dir.to_s, "savepoint.md")
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :savepoint_content

  def branch_ahead(runner, repo, target_branch, branch)
    return nil if blank?(target_branch) || blank?(branch)

    res = runner.run("-C", repo, "rev-list", "--count", "#{target_branch}..#{branch}")
    return nil unless res.success?

    res.stdout.to_s.strip.to_i
  end
  private_class_method :branch_ahead
end
