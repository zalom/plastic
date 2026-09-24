# encoding: UTF-8
# frozen_string_literal: true

require_relative "worktree"
require_relative "node_ledger"
require_relative "ready_set"
require_relative "savepoint"

# NodeWorktree (intent 340, G7, n3; git calls removed by intent 390 part B): a
# work node's own worktree, cut from the intent branch tip, merged back into
# the intent branch (never `alpha`), and swept once its node is terminal.
# Verify, research and decision nodes never get one (327 spec, C4: a verify
# node writes no code, so it gets nowhere to write a diff).
#
# The node worktree's identity is `<repo>/.claude/worktrees/<id>--<slug>--<node>`
# on branch `plastic/<id>--<slug>--<node>` - one path segment deeper than the
# intent worktree Worktree already provisions.
#
# Owner ruling 2026-09-24 (intent 390): Plastic runs no version control
# command. Every method here that used to shell out to git now computes the
# deterministic path/branch/commit-line and returns it as a printed
# instruction instead - it creates nothing, merges nothing, and removes
# nothing. The dispatch block, the absorb result, and the reaper's report
# carry the instruction text for the agent or the owner to run themselves.
#
# `changed_paths` is gone: the only source of truth left once git is out of
# the picture is the executor's own return (NodeReturn's schema), which
# carries no file list (ALLOWED_KEYS names node, status, commit, summary,
# findings, report, proposed_nodes, proposed_edges, question, reason). With
# nothing to measure a diff against, the scope check it fed is dropped too
# (RunnerAbsorb no longer runs a "scope" check) - a finding raised in this
# intent's record, not silently patched over with a fabricated file list.
#
# Pure: no `runner:` seam, no git call, no shell-out anywhere in this file.
module NodeWorktree
  module_function

  # Only a `work` node gets a worktree (matrix 3.4/3.5).
  WORKTREE_KINDS = %w[work].freeze

  # release(state:) names removal for these terminal states (matrix 3.8,
  # 3.11); every other state (failed_verification, needs_decision, or
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

  # provision(context, node:, kind:) -> {ok:, path:, branch:, provisioned:,
  # instruction:}. A non-`work` kind gets no worktree (matrix 3.4/3.5). An
  # unresolvable repo fails open (matrix 3.6): ok stays true, provisioned is
  # false, nothing raises. `provisioned` is true only when the path already
  # exists on disk (matrix 3.3, an earlier attempt's worktree reused) - this
  # method itself never creates one. `instruction` carries the `git worktree
  # add` command the dispatch block/agent runs, cut FROM the intent branch's
  # own tip (matrix 3.2), never from whatever the repo's main checkout
  # happens to have checked out.
  def provision(context, node:, kind:)
    return unprovisioned unless WORKTREE_KINDS.include?(kind.to_s)

    p = paths(context, node: node)
    repo, path, branch = p["repo"], p["path"], p["branch"]
    return unprovisioned if repo.nil?
    return { ok: true, path: path, branch: branch, provisioned: true, instruction: nil } if Dir.exist?(path)

    intent_branch = context.worktree_branch
    return unprovisioned if blank?(intent_branch)

    instruction = "git -C #{repo} worktree add #{path} -b #{branch} #{intent_branch}"
    { ok: true, path: path, branch: branch, provisioned: false, instruction: instruction }
  end

  # --- merging -----------------------------------------------------------------

  # merge(context, node:) -> {ok:, instruction:, error:}. Plastic never runs
  # this merge itself (owner ruling 2026-09-24): it names the merge INTO the
  # intent branch, IN the intent worktree (matrix 3.7) - never the repo's own
  # current branch - as a printed instruction for the agent or the owner to
  # run. RunnerAbsorb prints this instruction alongside a `done` transition
  # rather than blocking on a merge it can no longer verify itself (see that
  # module's own comment on the smaller-change decision).
  def merge(context, node:)
    p = paths(context, node: node)
    branch = p["branch"]
    intent_worktree = context.worktree

    if blank?(intent_worktree) || blank?(branch)
      return { ok: false, instruction: nil, error: "no intent worktree or node branch to merge" }
    end

    { ok: true, instruction: "git -C #{intent_worktree} merge --no-ff --no-edit #{branch}", error: nil }
  end

  # --- release (post-merge / post-terminal cleanup) -----------------------------

  # release(context, node:, state:) -> {ok:, removed:, instruction:}. Names
  # the removal instruction only for REMOVE_ON_STATES (matrix 3.8, 3.11);
  # every other state, and a worktree that is already gone, is left alone
  # (matrix 3.9, 3.10) - `removed` is always false now (Plastic itself
  # removes nothing), `instruction` carries the command when one applies.
  def release(context, node:, state:)
    p = paths(context, node: node)
    repo, path = p["repo"], p["path"]
    return { ok: true, removed: false, instruction: nil } if blank?(path) || !Dir.exist?(path)
    return { ok: true, removed: false, instruction: nil } unless REMOVE_ON_STATES.include?(state.to_s)

    { ok: true, removed: false, instruction: "git -C #{repo} worktree remove #{path}" }
  end

  # --- the reaper ----------------------------------------------------------------

  # reap(context) -> {removed: [], spared: [], instructions: [{node:, dir:,
  # instruction:}]}. Scoped to THIS intent's own node worktrees only (matrix
  # 3.18): globs `<repo>/.claude/worktrees/<id>--<slug>--*`, which by
  # construction never matches the intent's own worktree (`<id>--<slug>`, no
  # third segment) or any other intent's. Owner ruling 2026-09-24: Plastic
  # removes nothing itself, so `removed` is always empty now - a candidate
  # whose node resolves terminal (matrix 3.17) is named in `instructions`
  # instead, for the agent or the owner to run; anything not yet terminal is
  # spared exactly as before.
  def reap(context)
    repo = repo_root(context)
    return { removed: [], spared: [], instructions: [] } if repo.nil?

    base = File.join(repo, ".claude", "worktrees")
    return { removed: [], spared: [], instructions: [] } unless Dir.exist?(base)

    prefix = "#{context.intent_id}--#{context.intent_slug}--"
    status_map = NodeLedger.status_from_content(savepoint_content(context.intent_dir))

    spared = []
    instructions = []

    Dir.glob(File.join(base, "#{prefix}*")).select { |d| File.directory?(d) }.sort.each do |dir|
      node = File.basename(dir).sub(prefix, "")
      next unless node.match?(Savepoint::NODE_SUBJECT_RE)

      state = status_map.fetch(node, "planned")
      unless ReadySet::TERMINAL_STATES.include?(state)
        spared << { node: node, dir: dir, reason: "not terminal (#{state})" }
        next
      end

      instructions << { node: node, dir: dir, instruction: "git -C #{repo} worktree remove #{dir}" }
    end

    { removed: [], spared: spared, instructions: instructions }
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
    { ok: true, path: nil, branch: nil, provisioned: false, instruction: nil }
  end
  private_class_method :unprovisioned

  def savepoint_content(intent_dir)
    path = File.join(intent_dir.to_s, "savepoint.md")
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :savepoint_content
end
