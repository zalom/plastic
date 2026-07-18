# encoding: UTF-8
# frozen_string_literal: true

require_relative "worktree"
require_relative "bridge"

# WorktreeSweep -- the one-time orphan sweep for store worktrees retired by
# intent 178 (D2). Pure candidate classification plus a thin apply step, both
# dependency-injected (a ShellRunner, an explicit plastic_home) so the whole
# module is hermetically testable: no call here ever falls back to the real
# `Dir.home` (the intent 169 hermeticity lesson applies here too).
#
# A candidate is REMOVE iff its intent is terminal (Completed or Abandoned in
# SOME store's INDEX.md) AND its branch carries no commits ahead of that
# store's main. Any ambiguity -- no matching intent directory found in any
# store, an unreadable INDEX, or a branch that cannot be resolved -- SPARES
# the candidate rather than removing it. This module never shells out for
# `worktree remove`; that only happens in `apply!`, and only for candidates
# already marked REMOVE.
module WorktreeSweep
  module_function

  Candidate = Struct.new(:name, :dir, :branch, :intent_dir, :status, :ahead_count,
                         :decision, :reason, keyword_init: true)

  TERMINAL_STATUSES = %w[Completed Abandoned].freeze

  # All worktree dirs under `<plastic_home>/.worktrees/`, classified. `runner`
  # is injected (default a real ShellRunner) so tests never shell out.
  def candidates(plastic_home:, runner: Worktree::ShellRunner.new)
    Dir.glob(File.join(plastic_home, ".worktrees", "*"))
       .select { |d| File.directory?(d) }
       .sort
       .map { |dir| classify(dir, plastic_home: plastic_home, runner: runner) }
  end

  def classify(dir, plastic_home:, runner:)
    name = File.basename(dir)
    branch = "plastic-store/#{name}"
    intent_dir = resolve_intent_dir(plastic_home, name)
    status = intent_dir ? index_status(intent_dir, name) : nil
    ahead = intent_dir ? branch_ahead_count(runner, plastic_home, branch) : nil

    terminal = TERMINAL_STATUSES.include?(status)
    ahead_or_unknown = ahead.nil? || ahead > 0
    decision = (terminal && !ahead_or_unknown) ? :remove : :spare

    Candidate.new(name: name, dir: dir, branch: branch, intent_dir: intent_dir,
                  status: status, ahead_count: ahead, decision: decision,
                  reason: reason_for(intent_dir, status, ahead, terminal))
  end

  # The FIRST real intent directory literally named `{id}--{slug}` (the exact
  # worktree dir name) found under the global store or any project store.
  # Matching on the full name, not just the numeric id, sidesteps id
  # collisions across projects (ids are only unique WITHIN one store).
  def resolve_intent_dir(plastic_home, name)
    candidates = [File.join(plastic_home, "store", name)] +
                 Dir.glob(File.join(plastic_home, "projects", "*", "store", name))
    candidates.find { |d| Dir.exist?(d) }
  end

  # The INDEX.md section heading (e.g. "Active", "Completed") that lists this
  # intent dir, or nil if no INDEX.md entry links to it. Reuses
  # Bridge.index_entry_match so this never drifts from the shared parser.
  def index_status(intent_dir, name)
    store = File.dirname(intent_dir)
    index = File.join(File.dirname(store), "INDEX.md")
    return nil unless File.exist?(index)

    section = nil
    File.foreach(index) do |line|
      stripped = line.chomp
      if stripped.start_with?("## ")
        section = stripped.sub(/\A##\s*/, "").strip
        next
      end
      m = Bridge.index_entry_match(stripped)
      next unless m
      return section if m[3].to_s.include?(name)
    end
    nil
  end

  # Commits reachable from `branch` but not from the repo's own current
  # (default) branch, or nil if either cannot be resolved. nil is treated as
  # "ahead or unknown" by `classify` (fail SPARE, never fail REMOVE).
  def branch_ahead_count(runner, plastic_home, branch)
    target = Worktree.current_branch(runner, repo: plastic_home)
    return nil if target.nil? || target == branch
    res = runner.run("-C", plastic_home, "rev-list", "--count", "#{target}..#{branch}")
    return nil unless res.success?
    res.stdout.to_s.strip.to_i
  end

  def reason_for(intent_dir, status, ahead, terminal)
    return "no matching intent directory found in any store (orphaned/ambiguous reference)" unless intent_dir
    return "ahead of main by #{ahead} commit(s); sparing to avoid stranding unmerged work" if ahead.nil? || ahead > 0
    return "intent status is #{status.inspect}, not terminal; sparing" unless terminal
    "terminal (#{status}) and not ahead of main"
  end

  # A stable, human-reviewable dry-run report. Every candidate is listed,
  # remove and spare alike, with its full reasoning -- this is the artifact
  # the owner reviews BEFORE anything is deleted (D2, AC5).
  def dry_run_report(candidates, now: Time.now)
    lines = ["Store-worktree sweep dry run -- #{now.utc.iso8601}", ""]
    candidates.each do |c|
      tag = c.decision == :remove ? "REMOVE" : "SPARE "
      lines << "#{tag}  #{c.name}  status=#{c.status.inspect}  ahead=#{c.ahead_count.inspect}  #{c.reason}"
    end
    remove_n = candidates.count { |c| c.decision == :remove }
    lines << ""
    lines << "#{remove_n} of #{candidates.length} candidate(s) eligible for removal. " \
             "Nothing has been removed yet; re-run with --apply after review."
    lines.join("\n")
  end

  # Removes only :remove-decision candidates, via `git worktree remove` (falls
  # back to --force only inside Worktree.remove_worktree's own existing
  # retry), then `git worktree prune` once at the end. Returns the list of
  # candidates actually removed. Never called for a :spare candidate.
  def apply!(candidates, plastic_home:, runner: Worktree::ShellRunner.new)
    removed = candidates.select { |c| c.decision == :remove }
    removed.each { |c| Worktree.remove_worktree(runner, repo: plastic_home, worktree: c.dir) }
    Worktree.prune(runner, repo: plastic_home) unless removed.empty?
    removed
  end
end
