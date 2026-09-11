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

  # changed_paths(context, node:, kind:) -> the file paths a node's return
  # actually touched, or nil when that cannot be measured (matrix 3.13/3.14,
  # B3): a genuinely empty diff is [], never conflated with "the git call
  # itself could not run" or "there was nowhere to measure a diff at all" -
  # RunnerAbsorb treats nil as `failed_verification reason=scope_unmeasurable`,
  # never as a clean pass.
  #
  # A `work` node has its own branch (matrix 3.1-3.3), so its diff is the
  # ordinary two-branch comparison. A verify or research node gets no
  # worktree or branch of its own (D6, D29) - the only place such a node
  # could actually leave a diff is the shared INTENT worktree itself, so its
  # diff is measured there instead (row 9.9), never against a per-node
  # branch that, for these kinds, never exists (the exact fail-open B3
  # named: that lookup always failed and always read as "nothing changed").
  def changed_paths(context, node:, kind: "work", runner: Worktree::ShellRunner.new)
    if WORKTREE_KINDS.include?(kind.to_s)
      node_branch_diff(context, node: node, runner: runner)
    else
      intent_worktree_diff(context, runner: runner)
    end
  end

  def node_branch_diff(context, node:, runner:)
    p = paths(context, node: node)
    repo, branch = p["repo"], p["branch"]
    return nil if blank?(repo) || blank?(branch) || blank?(context.worktree_branch)

    res = runner.run("-C", repo, "diff", "--name-only", "#{context.worktree_branch}...#{branch}")
    return nil unless res.success?

    res.stdout.to_s.each_line.map(&:strip).reject(&:empty?)
  end
  private_class_method :node_branch_diff

  # A non-work node's diff, measured in the intent worktree itself (row 9.9)
  # against the last commit the ledger already knows is clean: the most
  # recent `done` transition's own `commit=` (any subject) - the intent
  # branch only ever advances past that point through a work node's own
  # merge (recorded there) or through exactly the kind of out-of-band commit
  # this check exists to catch. With no such transition recorded yet (no
  # work node has landed on this intent branch at all), the fork point with
  # the repo's own currently checked-out branch is the only other honest
  # baseline available; either baseline missing is "cannot measure" (nil),
  # never "clean" (matrix 3.6's fail-open direction reversed: unmeasurable
  # refuses here, it does not pass).
  def intent_worktree_diff(context, runner:)
    intent_worktree = context.worktree
    branch = context.worktree_branch
    return nil if blank?(intent_worktree) || blank?(branch)
    return nil unless Worktree.git_repo?(runner, intent_worktree)

    baseline = last_done_commit(context) || repo_fork_point(context, runner)
    return nil if blank?(baseline)

    res = runner.run("-C", intent_worktree, "diff", "--name-only", baseline, branch)
    return nil unless res.success?

    res.stdout.to_s.each_line.map(&:strip).reject(&:empty?)
  end
  private_class_method :intent_worktree_diff

  # The most recent `done` transition's own `commit=`, across every subject
  # in the ledger (torn lines excluded) - the last point RunnerAbsorb itself
  # already vouched for for as clean.
  def last_done_commit(context)
    content = savepoint_content(context.intent_dir)
    entries = NodeLedger.entries_from_content(content)
    entry = entries.reverse.find { |e| !e[:torn] && e[:state] == "done" && (e[:fields] || {})["commit"] }
    entry && entry[:fields]["commit"]
  end
  private_class_method :last_done_commit

  # merge-base(intent_branch, repo's own checked-out branch) - the point the
  # intent branch itself forked from (the repo's own checkout never receives
  # a node merge, so this stays stable across every later delivery), used
  # only when the ledger has no `done` commit yet to anchor on.
  def repo_fork_point(context, runner)
    repo = repo_root(context)
    return nil if repo.nil?

    current = Worktree.current_branch(runner, repo: repo)
    return nil if blank?(current)

    res = runner.run("-C", repo, "merge-base", context.worktree_branch, current)
    return nil unless res.success?

    sha = res.stdout.to_s.strip
    sha.empty? ? nil : sha
  end
  private_class_method :repo_fork_point

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
