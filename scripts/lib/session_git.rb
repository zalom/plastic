# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require_relative "worktree"
require_relative "scaffold_intent"
require_relative "session_ledger"

# SessionGit - the branch model and per-repo flow settings behind
# `scripts/session-commit` (intent 300), which is how a checklist item
# verified during a session becomes one git commit on the right branch of
# the repository that contains it. Implements the ruling recorded in intent
# 296's "Branch model" section: a session branch per repository per day cut
# from that repository's own base branch under `mode: direct`, or a small
# branch-and-PR per item under `mode: pull_request`.
#
# Pure and dependency-injected: every git call goes through an injected
# `runner:` (default `Worktree::ShellRunner.new`, the same seam Worktree
# itself uses), every `gh` call goes through an injected `gh_runner:`
# (default `SessionGit::GhRunner.new`, since `gh` is not `git` and needs its
# own seam), and this file reads no environment variable anywhere -- only
# `scripts/session-commit` reads the environment and passes what it read in.
module SessionGit
  module_function

  MODES = %w[direct pull_request].freeze
  WORKSPACES = %w[checkout worktree].freeze
  MAX_SUBJECT_LENGTH = 72

  DEFAULT_BRANCH_TEMPLATE = "session/{{day}}"

  # One outcome, always. `event` is "Item" (a commit landed on the happy
  # path: the session branch was fast-forwarded into the base, or a PR
  # opened) or "Note" (every degradation: no repo, nothing to commit, an
  # agent-owned branch, a wrong branch, a refused push, a missing `gh`, a
  # rejected commit-msg hook, or an unknown flow value). `message` is both
  # the CLI's stdout line and the ledger's savepoint summary (spec D1: "the
  # same text as a Note or Item savepoint line").
  Result = Struct.new(:message, :event, keyword_init: true)

  # The default `gh` seam. `gh` is a different executable than `git`, so it
  # cannot reuse Worktree::ShellRunner's git-only `run`. `available?` probes
  # PATH the same way a shell would (no environment-variable read: `system`
  # resolves PATH itself via the OS, the same as typing `gh` at a prompt).
  class GhRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def available?
      system("gh", "--version", out: File::NULL, err: File::NULL) == true
    end

    def run(*args)
      require "open3"
      out, err, status = Open3.capture3("gh", *args.map(&:to_s))
      Result.new(status.exitstatus.to_i, out, err)
    end
  end

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # --- repo resolution --------------------------------------------------------

  # The repo root containing `cwd`, or nil when `cwd` is outside any git
  # repository (spec D2).
  def resolve_repo(cwd, runner:)
    res = runner.run("-C", cwd.to_s, "rev-parse", "--show-toplevel")
    return nil unless res.success?

    top = res.stdout.to_s.strip
    top.empty? ? nil : top
  end

  # --- flow resolution ---------------------------------------------------------

  # [flow_hash, notes]. `flow_hash` always carries all five knobs (spec D2):
  # mode, base, branch_template, ticket_source, workspace. `notes` is a list
  # of human-readable strings for every unknown `mode` or `workspace` value
  # found in the project's `flow:` block, each of which degrades the whole
  # outcome to a Note savepoint line (see SessionGit.commit!).
  def load_flow(cwd:, repo:, plastic_home:, runner:)
    notes = []
    slug = SessionLedger.project_slug(cwd, plastic_home: plastic_home)
    project_flow = read_project_flow(slug, plastic_home)

    base_default = repo ? ScaffoldIntent.detect_base_branch(repo, runner: runner) : nil

    flow = {
      "mode" => "direct",
      "base" => base_default,
      "branch_template" => DEFAULT_BRANCH_TEMPLATE,
      "ticket_source" => "intent_id",
      "workspace" => "checkout",
    }

    if project_flow
      flow["base"] = project_flow["base"].to_s unless blank?(project_flow["base"])
      unless blank?(project_flow["branch_template"])
        flow["branch_template"] = project_flow["branch_template"].to_s
      end
      unless blank?(project_flow["ticket_source"])
        flow["ticket_source"] = project_flow["ticket_source"].to_s
      end

      apply_enum_knob!(flow, notes, project_flow, key: "mode", allowed: MODES, default: "direct")
      apply_enum_knob!(flow, notes, project_flow, key: "workspace", allowed: WORKSPACES, default: "checkout")
    end

    [flow, notes]
  end

  def apply_enum_knob!(flow, notes, project_flow, key:, allowed:, default:)
    value = project_flow[key]
    return if blank?(value)

    if allowed.include?(value.to_s)
      flow[key] = value.to_s
    else
      notes << "unknown flow #{key} #{value.inspect}, using default: #{default}"
    end
  end

  def read_project_flow(slug, plastic_home)
    return nil if slug == "global"

    project_yml = File.join(plastic_home, "projects", slug, "project.yml")
    return nil unless File.exist?(project_yml)

    data = begin
      YAML.safe_load(File.read(project_yml))
    rescue StandardError
      nil
    end
    data.is_a?(Hash) && data["flow"].is_a?(Hash) ? data["flow"] : nil
  end

  # --- token rendering ----------------------------------------------------------

  def render_branch(template, day:, ticket:, slug:)
    template.to_s
            .gsub("{{day}}", day.to_s)
            .gsub("{{ticket}}", ticket.to_s)
            .gsub("{{slug}}", slug.to_s)
  end

  # Kebab-case the first `max_words` words of `text`. Used to build the
  # `{{slug}}` token for a pull-request branch name (spec D4).
  def summary_slug(text, max_words: 5)
    text.to_s.downcase.scan(/[a-z0-9]+/).first(max_words).join("-")
  end

  # The intent id named by the session's pointer file when `ticket_source`
  # is `intent_id`, else the day id (spec D4). Per intent 298 spec D6, the
  # pointer at `.tmp/<session>/current` holds exactly one line: either
  # today's day id (the session records into the day ledger) or an intent
  # id (an auto team owns the record). A day id in the pointer is therefore
  # not an intent name, and falls back to the day id here too, which is the
  # same value either way.
  def resolve_ticket(day:, store:, session:, ticket_source:)
    return day.to_s unless ticket_source.to_s == "intent_id"

    pointer = SessionLedger.pointer_path(store, session)
    return day.to_s unless File.exist?(pointer)

    content = File.read(pointer).to_s.strip
    return day.to_s if content.empty?
    return day.to_s if SessionLedger.valid_day_id?(content)

    content
  end

  # --- commit message ------------------------------------------------------------

  # The first line of `summary`, truncated to MAX_SUBJECT_LENGTH characters,
  # with no trailer (spec D5).
  def subject_for(summary)
    first_line = summary.to_s.split(/\r?\n/, 2).first.to_s.strip
    first_line[0, MAX_SUBJECT_LENGTH]
  end

  # --- git primitives (all use -C, never cwd) -------------------------------------

  def current_branch(repo, runner:)
    res = runner.run("-C", repo, "rev-parse", "--abbrev-ref", "HEAD")
    return nil unless res.success?

    res.stdout.to_s.strip
  end

  def dirty?(repo, runner:)
    res = runner.run("-C", repo, "status", "--porcelain")
    res.success? && !res.stdout.to_s.strip.empty?
  end

  def branch_exists?(repo, branch, runner:)
    runner.run("-C", repo, "rev-parse", "--verify", "--quiet", branch).success?
  end

  # True iff `branch` is a branch an agent owns and this library must never
  # touch (spec D3b): its name starts with `plastic/` (every Plastic intent
  # worktree's branch, per Worktree.paths), or `repo` itself is a worktree
  # checked out under `.claude/worktrees/` on some OTHER name. The session's
  # own worktree (`.claude/worktrees/session-<day>`, spec D8) is deliberately
  # exempted from the second clause: it is this library's own workspace, not
  # another agent's, so its basename is matched and excluded here rather than
  # flagged as a lock on itself.
  def agent_owned?(repo, branch)
    return true if branch.to_s.start_with?("plastic/")

    parts = File.expand_path(repo.to_s).split(File::SEPARATOR)
    parts.each_cons(2).any? do |a, b|
      a == ".claude" && b == "worktrees" && !session_worktree_name?(parts.last)
    end
  end

  SESSION_WORKTREE_NAME = /\Asession-\d{8}\z/.freeze
  private_constant :SESSION_WORKTREE_NAME

  def session_worktree_name?(name)
    SESSION_WORKTREE_NAME.match?(name.to_s)
  end

  def stage_and_commit(dir, subject, runner:)
    runner.run("-C", dir, "add", "-A")
    runner.run("-C", dir, "commit", "-m", subject)
  end

  def short_sha(dir, runner:)
    res = runner.run("-C", dir, "rev-parse", "--short", "HEAD")
    return nil unless res.success?

    res.stdout.to_s.strip
  end

  # --- the branch model (spec D3, D4) ----------------------------------------------

  # Resolve the repo and flow for `cwd`, apply the branch model, and return
  # the one Result the caller writes to the ledger. Fail-open throughout:
  # every branch of this method returns a Result, never raises, and the CLI
  # always exits 0 (spec D1).
  def commit!(cwd:, summary:, day:, session:, plastic_home:, store: nil,
              runner: Worktree::ShellRunner.new, gh_runner: GhRunner.new)
    effective_store = store || File.join(plastic_home, "store")
    repo = resolve_repo(cwd, runner: runner)
    return Result.new(message: "no repo", event: "Note") if repo.nil?

    flow, flow_notes = load_flow(cwd: cwd, repo: repo, plastic_home: plastic_home, runner: runner)
    subject = subject_for(summary)

    result =
      if flow["mode"] == "pull_request"
        commit_pull_request(repo: repo, subject: subject, day: day, session: session,
                             store: effective_store, flow: flow, runner: runner, gh_runner: gh_runner)
      else
        commit_direct(repo: repo, subject: subject, day: day, flow: flow, runner: runner)
      end

    return result if flow_notes.empty?

    # An unknown mode or workspace value is itself a degradation (spec D2),
    # so it always turns the outcome into a Note, folding both facts into
    # the single savepoint line spec D7 allows.
    Result.new(message: "#{flow_notes.join('; ')}; #{result.message}", event: "Note")
  end

  # --- direct mode (spec D3) --------------------------------------------------------

  def commit_direct(repo:, subject:, day:, flow:, runner:)
    branch_now = current_branch(repo, runner: runner)
    return note("detached HEAD: no commit") if blank?(branch_now) || branch_now == "HEAD"
    return note("left branch #{branch_now} untouched: agent lock") if agent_owned?(repo, branch_now)
    return note("nothing to commit") unless dirty?(repo, runner: runner)

    base = flow["base"]
    return note("no base branch detected") if blank?(base)

    session_branch = render_branch(flow["branch_template"], day: day, ticket: "", slug: "")

    if branch_now == base || branch_now == session_branch
      if flow["workspace"] == "worktree"
        commit_on_session_worktree(repo: repo, subject: subject, base: base,
                                    session_branch: session_branch, day: day, runner: runner)
      else
        commit_on_session_branch(repo: repo, subject: subject, base: base,
                                  session_branch: session_branch, branch_now: branch_now, runner: runner)
      end
    else
      commit_on_other_branch(repo: repo, subject: subject, branch_now: branch_now, runner: runner)
    end
  end

  def note(message)
    Result.new(message: message, event: "Note")
  end

  def commit_on_session_branch(repo:, subject:, base:, session_branch:, branch_now:, runner:)
    runner.run("-C", repo, "branch", session_branch, base.to_s) unless branch_exists?(repo, session_branch, runner: runner)
    runner.run("-C", repo, "checkout", session_branch) unless branch_now == session_branch

    commit_and_push(dir: repo, push_dir: repo, subject: subject, from: session_branch, base: base, runner: runner)
  end

  # workspace: worktree (spec D8): the item's dirty tree, physically sitting
  # in `repo`'s own checkout, is relocated into a dedicated worktree for the
  # session branch via `git stash` (which is repo-wide, shared across every
  # worktree of the same repository, so a stash pushed in `repo` can be
  # popped in the sibling worktree) rather than switching `repo`'s own
  # checkout onto the session branch, which is exactly what workspace:
  # worktree exists to avoid (296's research: a checked-out branch switch
  # under the owner's feet costs dev-server/port/database visibility).
  def commit_on_session_worktree(repo:, subject:, base:, session_branch:, day:, runner:)
    worktree_path = File.join(repo, ".claude", "worktrees", "session-#{day}")

    unless Dir.exist?(worktree_path)
      Worktree.ensure_gitignored(repo, ".claude/worktrees/", runner: runner)
      if branch_exists?(repo, session_branch, runner: runner)
        runner.run("-C", repo, "worktree", "add", worktree_path, session_branch)
      else
        runner.run("-C", repo, "worktree", "add", worktree_path, "-b", session_branch, base.to_s)
      end
    end

    stash = runner.run("-C", repo, "stash", "push", "--include-untracked", "-m", "session-commit")
    return note("nothing to commit") unless stash.success? && !stash.stdout.to_s.include?("No local changes to save")

    pop = runner.run("-C", worktree_path, "stash", "pop")
    unless pop.success?
      runner.run("-C", repo, "stash", "pop")
      return note("workspace: worktree relocation failed: #{pop.stderr.to_s.strip}")
    end

    finish_worktree_commit(worktree_path: worktree_path, repo: repo, subject: subject,
                            session_branch: session_branch, base: base, runner: runner)
  end

  # `repo` (the main checkout) stays on `base` throughout workspace: worktree
  # (that is the point of the knob), so integrating the worktree's new
  # commit cannot go through `git push . S:B` the way the plain checkout
  # path does: git unconditionally refuses a push into a branch checked out
  # in ANOTHER working tree of the same repository, fast-forward or not
  # (`! [remote rejected] ... (branch is currently checked out)`). Since
  # `repo`'s working tree is clean at this point (its dirty files were
  # already relocated into the worktree above), a plain `git merge --ff-only`
  # run FROM `repo` both moves `base` and updates `repo`'s working tree in
  # the one git-native operation designed for exactly this.
  def finish_worktree_commit(worktree_path:, repo:, subject:, session_branch:, base:, runner:)
    res = stage_and_commit(worktree_path, subject, runner: runner)
    return note("commit rejected by commit-msg hook: #{res.stderr.to_s.strip}") unless res.success?

    sha = short_sha(worktree_path, runner: runner)
    merge = runner.run("-C", repo, "merge", "--ff-only", session_branch)
    if merge.success?
      Result.new(message: "#{subject} (#{sha})", event: "Item")
    else
      note("committed #{subject} (#{sha}) on #{session_branch}, push to #{base} refused: not a fast-forward")
    end
  end

  def commit_on_other_branch(repo:, subject:, branch_now:, runner:)
    res = stage_and_commit(repo, subject, runner: runner)
    return note("commit rejected by commit-msg hook: #{res.stderr.to_s.strip}") unless res.success?

    sha = short_sha(repo, runner: runner)
    note("committed #{subject} (#{sha}) on #{branch_now}, not the session branch")
  end

  # Stage, commit, and (attempt to) fast-forward `base` from `from` in one
  # shared tail, used by both the checkout and the worktree happy paths. A
  # non-fast-forward push (spec D3, "base moved ahead independently") stays
  # a Note: the commit itself already landed on the session branch.
  def commit_and_push(dir:, push_dir:, subject:, from:, base:, runner:)
    res = stage_and_commit(dir, subject, runner: runner)
    return note("commit rejected by commit-msg hook: #{res.stderr.to_s.strip}") unless res.success?

    sha = short_sha(dir, runner: runner)
    push = runner.run("-C", push_dir, "push", ".", "#{from}:#{base}")
    if push.success?
      runner.run("-C", dir, "merge", "--ff-only", base.to_s)
      Result.new(message: "#{subject} (#{sha})", event: "Item")
    else
      note("committed #{subject} (#{sha}) on #{from}, push to #{base} refused: not a fast-forward")
    end
  end

  # --- pull request mode (spec D4) ------------------------------------------------

  def commit_pull_request(repo:, subject:, day:, session:, store:, flow:, runner:, gh_runner:)
    previous_branch = current_branch(repo, runner: runner)
    return note("nothing to commit") unless dirty?(repo, runner: runner)

    base = flow["base"]
    return note("no base branch detected") if blank?(base)

    ticket = resolve_ticket(day: day, store: store, session: session, ticket_source: flow["ticket_source"])
    slug = summary_slug(subject)
    branch = render_branch(flow["branch_template"], day: day, ticket: ticket, slug: slug)

    runner.run("-C", repo, "branch", branch, base.to_s) unless branch_exists?(repo, branch, runner: runner)
    runner.run("-C", repo, "checkout", branch) unless previous_branch == branch

    res = stage_and_commit(repo, subject, runner: runner)
    outcome =
      if res.success?
        pull_request_outcome(repo: repo, subject: subject, branch: branch, base: base, gh_runner: gh_runner, runner: runner)
      else
        note("commit rejected by commit-msg hook: #{res.stderr.to_s.strip}")
      end

    if previous_branch && previous_branch != "HEAD" && previous_branch != branch
      runner.run("-C", repo, "checkout", previous_branch)
    end

    outcome
  end

  def pull_request_outcome(repo:, subject:, branch:, base:, gh_runner:, runner:)
    sha = short_sha(repo, runner: runner)
    return note("gh missing") unless gh_runner.available?

    pr = gh_runner.run("pr", "create", "--base", base.to_s, "--head", branch, "--fill")
    if pr.success?
      url = pr.stdout.to_s.strip.lines.last.to_s.strip
      Result.new(message: "pr #{url}", event: "Item")
    else
      note("committed #{subject} (#{sha}) on #{branch}: gh pr create failed: #{pr.stderr.to_s.strip}")
    end
  end
end
