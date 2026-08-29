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
  WORKSPACE_WORKTREE_NOTE = "workspace: worktree is not implemented in this release; " \
                            "committed through the checkout"

  # One outcome, always. `event` is "Item" (a commit landed on the happy
  # path: the session branch was fast-forwarded into the base, or a PR
  # opened) or "Note" (every degradation: no repo, nothing to commit, an
  # agent-owned branch, a wrong branch, a refused push or checkout, a
  # missing `gh`, a rejected commit-msg hook, an unknown or unimplemented
  # flow value). `message` is both the CLI's stdout line and the ledger's
  # savepoint summary (spec D1: "the same text as a Note or Item savepoint
  # line").
  Result = Struct.new(:message, :event, keyword_init: true)

  # The default `gh` seam. `gh` is a different executable than `git`, so it
  # cannot reuse Worktree::ShellRunner's git-only `run`. Every call takes an
  # explicit `dir:` and runs there (review R1): without it, `gh pr create`
  # resolves its target repository from the calling process's own working
  # directory, not `--cwd`'s repo, which is the one place this library could
  # otherwise act on a repository other than the one it was asked about.
  # `available?` probes PATH the same way a shell would (no
  # environment-variable read: `system` resolves PATH itself via the OS, the
  # same as typing `gh` at a prompt).
  class GhRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def available?(dir = nil)
      opts = dir ? { chdir: dir } : {}
      system("gh", "--version", out: File::NULL, err: File::NULL, **opts) == true
    end

    def run(*args, dir: nil)
      require "open3"
      opts = dir ? { chdir: dir } : {}
      out, err, status = Open3.capture3("gh", *args.map(&:to_s), **opts)
      Result.new(status.exitstatus.to_i, out, err)
    end
  end

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  def note(message)
    Result.new(message: message, event: "Note")
  end

  # `res.stderr`, falling back to `res.stdout` when stderr is empty (review
  # N2): a hook or a git subcommand can write its explanation to either
  # stream, and an empty diagnosis is worse than a stdout-sourced one.
  def diagnose(res)
    text = res.stderr.to_s.strip
    return text unless text.empty?

    res.stdout.to_s.strip
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
  # found in the project's `flow:` block, plus `workspace: worktree` itself
  # (review BLOCKER 3 ruling: the knob stays a valid config value, but its
  # real implementation is a follow-up, so it is treated as `checkout` and
  # always degrades the outcome to a Note). See SessionGit.commit!.
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

    if flow["workspace"] == "worktree"
      flow["workspace"] = "checkout"
      notes << WORKSPACE_WORKTREE_NOTE
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

  # The branch HEAD points to, even on an unborn branch (review R3: a fresh
  # `git init`, zero commits). `git rev-parse --abbrev-ref HEAD` FAILS on an
  # unborn branch (there is no commit for it to resolve yet), which the old
  # implementation misread as "cannot determine a branch" and folded into
  # the detached-HEAD case. `git symbolic-ref --quiet --short HEAD` succeeds
  # on both a normal AND an unborn branch (HEAD is a symbolic ref to
  # `refs/heads/<name>` in both cases) and only fails when HEAD is
  # genuinely detached, which is exactly the distinction this method needs.
  # Returns the literal string "HEAD" for a detached HEAD (matched by
  # callers below), and the real branch name otherwise.
  def current_branch(repo, runner:)
    sym = runner.run("-C", repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    return sym.stdout.to_s.strip if sym.success?

    "HEAD"
  end

  # True iff `repo` has at least one commit. An unborn branch (current_branch
  # returns a real name, but there is nothing to commit onto as a base yet)
  # is otherwise indistinguishable from a normal repo until a git command
  # that needs a resolvable HEAD is attempted and fails partway through.
  def has_commits?(repo, runner:)
    runner.run("-C", repo, "rev-parse", "--verify", "--quiet", "HEAD").success?
  end

  def dirty?(repo, runner:)
    res = runner.run("-C", repo, "status", "--porcelain")
    res.success? && !res.stdout.to_s.strip.empty?
  end

  def branch_exists?(repo, branch, runner:)
    runner.run("-C", repo, "rev-parse", "--verify", "--quiet", branch).success?
  end

  # True iff `name` is a syntactically valid git branch name (review
  # BLOCKER 2): a `branch_template` that renders an empty or malformed ref
  # (a stray `{{ticket}}` left unpopulated in direct mode, for one) must
  # never reach `git branch`/`git checkout`, whose failure this library
  # already has to handle regardless, but which is cheaper and clearer to
  # catch before ever attempting.
  def valid_branch_name?(name, runner:)
    return false if blank?(name)

    runner.run("check-ref-format", "--branch", name.to_s).success?
  end

  # True iff `branch` is a branch an agent owns and this library must never
  # touch (spec D3b): its name starts with `plastic/` (every Plastic intent
  # worktree's branch, per Worktree.paths), or `repo` itself is a worktree
  # checked out under `.claude/worktrees/`.
  def agent_owned?(repo, branch)
    return true if branch.to_s.start_with?("plastic/")

    parts = File.expand_path(repo.to_s).split(File::SEPARATOR)
    parts.each_cons(2).any? { |a, b| a == ".claude" && b == "worktrees" }
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
  #
  # The detached-HEAD, agent-lock, and unborn-repo guards run here, BEFORE
  # the mode dispatch (review BLOCKER 1): they used to live only inside
  # commit_direct, so `mode: pull_request` skipped them entirely and could
  # switch a checkout holding another agent's uncommitted work, or commit on
  # a detached HEAD. Both modes now share exactly one check of each.
  def commit!(cwd:, summary:, day:, session:, plastic_home:, store: nil,
              runner: Worktree::ShellRunner.new, gh_runner: GhRunner.new)
    effective_store = store || File.join(plastic_home, "store")
    repo = resolve_repo(cwd, runner: runner)
    return note("no repo") if repo.nil?

    branch_now = current_branch(repo, runner: runner)
    return note("detached HEAD: no commit") if branch_now == "HEAD"
    return note("left branch #{branch_now} untouched: agent lock") if agent_owned?(repo, branch_now)
    return note("repository has no commits yet: no commit") unless has_commits?(repo, runner: runner)

    flow, flow_notes = load_flow(cwd: cwd, repo: repo, plastic_home: plastic_home, runner: runner)
    subject = subject_for(summary)

    result =
      if flow["mode"] == "pull_request"
        commit_pull_request(repo: repo, subject: subject, day: day, session: session,
                             store: effective_store, flow: flow, branch_now: branch_now,
                             runner: runner, gh_runner: gh_runner)
      else
        commit_direct(repo: repo, subject: subject, day: day, flow: flow, branch_now: branch_now, runner: runner)
      end

    return result if flow_notes.empty?

    # An unknown mode/workspace value, or workspace: worktree's degradation
    # to checkout, is itself a degradation (spec D2, BLOCKER 3 ruling), so
    # it always turns the outcome into a Note, folding both facts into the
    # single savepoint line spec D7 allows.
    Result.new(message: "#{flow_notes.join('; ')}; #{result.message}", event: "Note")
  end

  # --- direct mode (spec D3) --------------------------------------------------------

  def commit_direct(repo:, subject:, day:, flow:, branch_now:, runner:)
    return note("nothing to commit") unless dirty?(repo, runner: runner)
    return note("summary is empty after truncation: no commit") if blank?(subject)

    base = flow["base"]
    return note("no base branch detected") if blank?(base)
    return note("configured base #{base} does not exist") unless branch_exists?(repo, base, runner: runner)

    template = flow["branch_template"]
    if template.to_s.include?("{{ticket}}") || template.to_s.include?("{{slug}}")
      return note("branch_template #{template} needs {{ticket}} or {{slug}}, which direct mode " \
                   "leaves empty; configure a {{day}}-only template for direct mode")
    end

    session_branch = render_branch(template, day: day, ticket: "", slug: "")
    unless valid_branch_name?(session_branch, runner: runner)
      return note("rendered branch name #{session_branch.inspect} is not a valid git ref; check branch_template")
    end

    if branch_now == base || branch_now == session_branch
      commit_on_session_branch(repo: repo, subject: subject, base: base,
                                session_branch: session_branch, branch_now: branch_now, runner: runner)
    else
      commit_on_other_branch(repo: repo, subject: subject, branch_now: branch_now, runner: runner)
    end
  end

  # Every state-changing git call is checked (review BLOCKER 2): a
  # `git branch` or `git checkout` failure (a conflicting dirty file, the
  # session branch already checked out in a sibling worktree, and so on)
  # used to be ignored, so staging and committing ran unconditionally in
  # `repo` regardless of which branch was actually checked out afterward,
  # landing the item straight on the base branch while the Note claimed the
  # session branch. `current_branch` is re-read after the switch and used
  # for the commit message instead of trusting the branch this method
  # intended to reach.
  def commit_on_session_branch(repo:, subject:, base:, session_branch:, branch_now:, runner:)
    unless branch_exists?(repo, session_branch, runner: runner)
      create = runner.run("-C", repo, "branch", session_branch, base.to_s)
      return note("could not create session branch #{session_branch}: #{diagnose(create)}") unless create.success?
    end

    if branch_now != session_branch
      switch = runner.run("-C", repo, "checkout", session_branch)
      return note("could not check out session branch #{session_branch}: #{diagnose(switch)}") unless switch.success?
    end

    actual_branch = current_branch(repo, runner: runner)
    unless actual_branch == session_branch
      return note("expected to be on #{session_branch} but the checkout is on #{actual_branch.inspect}")
    end

    commit_and_push(dir: repo, push_dir: repo, subject: subject, from: actual_branch, base: base, runner: runner)
  end

  def commit_on_other_branch(repo:, subject:, branch_now:, runner:)
    res = stage_and_commit(repo, subject, runner: runner)
    return note("commit rejected by commit-msg hook: #{diagnose(res)}") unless res.success?

    sha = short_sha(repo, runner: runner)
    note("committed #{subject} (#{sha}) on #{branch_now}, not the session branch")
  end

  # Stage, commit, and (attempt to) fast-forward `base` from `from` in one
  # shared tail. A non-fast-forward push (spec D3, "base moved ahead
  # independently") stays a Note: the commit itself already landed on the
  # session branch.
  def commit_and_push(dir:, push_dir:, subject:, from:, base:, runner:)
    res = stage_and_commit(dir, subject, runner: runner)
    return note("commit rejected by commit-msg hook: #{diagnose(res)}") unless res.success?

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

  def commit_pull_request(repo:, subject:, day:, session:, store:, flow:, branch_now:, runner:, gh_runner:)
    return note("nothing to commit") unless dirty?(repo, runner: runner)
    return note("summary is empty after truncation: no commit") if blank?(subject)

    base = flow["base"]
    return note("no base branch detected") if blank?(base)
    return note("configured base #{base} does not exist") unless branch_exists?(repo, base, runner: runner)

    ticket = resolve_ticket(day: day, store: store, session: session, ticket_source: flow["ticket_source"])
    slug = summary_slug(subject)
    branch = render_branch(flow["branch_template"], day: day, ticket: ticket, slug: slug)
    unless valid_branch_name?(branch, runner: runner)
      return note("rendered branch name #{branch.inspect} is not a valid git ref; check branch_template")
    end

    unless branch_exists?(repo, branch, runner: runner)
      create = runner.run("-C", repo, "branch", branch, base.to_s)
      return note("could not create branch #{branch}: #{diagnose(create)}") unless create.success?
    end

    if branch_now != branch
      switch = runner.run("-C", repo, "checkout", branch)
      return note("could not check out branch #{branch}: #{diagnose(switch)}") unless switch.success?
    end

    res = stage_and_commit(repo, subject, runner: runner)
    outcome =
      if res.success?
        pull_request_outcome(repo: repo, subject: subject, branch: branch, base: base, gh_runner: gh_runner, runner: runner)
      else
        note("commit rejected by commit-msg hook: #{diagnose(res)}")
      end

    if branch_now != branch
      runner.run("-C", repo, "checkout", branch_now)
    end

    outcome
  end

  def pull_request_outcome(repo:, subject:, branch:, base:, gh_runner:, runner:)
    sha = short_sha(repo, runner: runner)
    return note("gh missing: commit #{subject} (#{sha}) is on #{branch}") unless gh_runner.available?(repo)

    pr = gh_runner.run("pr", "create", "--base", base.to_s, "--head", branch, "--fill", dir: repo)
    if pr.success?
      url = pr.stdout.to_s.strip.lines.last.to_s.strip
      Result.new(message: "pr #{url}", event: "Item")
    else
      note("committed #{subject} (#{sha}) on #{branch}: gh pr create failed: #{diagnose(pr)}")
    end
  end
end
