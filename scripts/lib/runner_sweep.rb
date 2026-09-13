# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "fileutils"
require_relative "worktree"
require_relative "lock"
require_relative "node_ledger"
require_relative "ready_set"
require_relative "savepoint"

# RunnerSweep (intent 340, G7, n2): the first thing every `step` does. Two
# separately callable entry points - #abort_if_merging and #reclaim - plus
# #run, which composes them for a caller that has no absorb step to interleave.
# `step` (a later node) calls #abort_if_merging, runs absorb, then calls
# #reclaim itself, so a reclaimed node's just-landed work from absorb is never
# thrown away by a stale read (matrix row 2.20).
#
# #abort_if_merging refuses the whole step when the intent worktree already
# has a merge in progress (`MERGE_HEAD` resolves): dispatching on top of a
# half-finished merge would hand the next node a diff full of someone else's
# conflict markers. Nothing is written when this fires - not the ledger, not
# graph.md, not even the delivery lease heartbeat (row 2.2, row 2.16: the
# heartbeat runs strictly after the abort check).
#
# #reclaim walks every node whose CURRENT status (the ledger's own resolution,
# never a raw scan) is `running`, skipping anything named in `skip:` (the
# nodes this step already absorbed, row 2.19) or already terminal (a `done`
# node is never touched, row 2.12 - it simply never shows up as `running`).
# An expired lease with no commits on the node's own branch newer than its
# expiry is reclaimed outright. An expired lease whose branch DOES carry
# newer commits is extended instead, up to twice per attempt (row 2.7); the
# extension is never a ledger transition (`running` cannot re-enter `running`
# under the transition layer), so it is one line appended to
# attempts/<node>--a<N>.extensions, `N` derived from the ledger's own attempt
# count (row 2.18), never trusted from the caller. A third expiry reclaims
# regardless of new commits.
#
# Pure and dependency-injected: every git call goes through an injected
# `runner:` (default Worktree::ShellRunner), never cwd; the delivery-lease
# heartbeat goes through an injected `heartbeat:` (default Lock.heartbeat) so
# ordering (row 2.16) is provable without a real lock file. No eval, no
# ENV/global-constant seam.
module RunnerSweep
  module_function

  # D-ish: at most two extensions per attempt (row 2.7); the third expiry
  # reclaims regardless of new commits.
  MAX_EXTENSIONS_PER_ATTEMPT = 2

  # abort_if_merging(context, runner:) -> {ok:, error:, recovery_command:}.
  # `context.worktree` is nil for a global-store-only intent (no git repo to
  # merge into); that case is always ok - there is nothing to abort.
  def abort_if_merging(context, runner: Worktree::ShellRunner.new)
    worktree = context&.worktree
    return { ok: true, error: nil, recovery_command: nil } if blank?(worktree)

    res = runner.run("-C", worktree, "rev-parse", "-q", "--verify", "MERGE_HEAD")
    return { ok: true, error: nil, recovery_command: nil } unless res.success?

    recovery_command = "git -C #{worktree} merge --abort"
    warn "runner: a merge is already in progress in #{worktree}; run `#{recovery_command}` " \
         "before the next step can dispatch"
    { ok: false, error: "a merge is in progress in #{worktree}", recovery_command: recovery_command }
  end

  # reclaim(context, runner:, skip:, now:) -> {reclaimed: [{node:, holder:,
  # expired:}], extended: [{node:, head:, time:}]}. Reads the ledger fresh on
  # every call (no cache), which is what makes calling it AFTER absorb (row
  # 2.20) actually see absorb's own just-landed work rather than a stale
  # snapshot taken before it.
  def reclaim(context, runner: Worktree::ShellRunner.new, skip: [], now: Time.now)
    intent_dir = context.intent_dir
    content = savepoint_content(intent_dir)
    entries = NodeLedger.entries_from_content(content)
    status_map = NodeLedger.status_from_content(content)
    skip_set = Array(skip).map(&:to_s)

    reclaimed = []
    extended = []

    status_map.each do |subject, state|
      next unless state == "running"
      next unless subject.match?(Savepoint::NODE_SUBJECT_RE)
      next if skip_set.include?(subject)

      last = entries.select { |e| !e[:torn] && e[:subject] == subject && e[:state] == "running" }.last
      next unless last

      fields = last[:fields] || {}
      expires_raw = fields["expires"]
      expires_at = parse_time(expires_raw)
      next unless expires_at
      next if now < expires_at # row 2.5: an unexpired lease is left alone

      holder = fields["holder"]
      branch = node_branch(context, subject)
      head_sha, head_time = branch_head(runner, context.worktree, branch)
      has_new_commits = head_time && head_time > expires_at

      if has_new_commits
        attempt = current_attempt(entries, subject)
        count = extension_count(intent_dir, subject, attempt)
        if count < MAX_EXTENSIONS_PER_ATTEMPT
          record_extension(intent_dir, subject, attempt, head_sha, now)
          extended << { node: subject, head: head_sha, time: now.utc.iso8601 }
          next
        end
        # row 2.7: the cap is spent - fall through and reclaim anyway.
      end

      NodeLedger.append_transition(
        savepoint_path(intent_dir),
        subject: subject,
        state: "reclaimed",
        fields: { holder: holder, expired: expires_raw },
        now: now
      )
      reclaimed << { node: subject, holder: holder, expired: expires_raw }
    end

    { reclaimed: reclaimed, extended: extended }
  end

  # run(context, runner:, skip:, now:, heartbeat:) -> the composed report a
  # caller with no absorb step to interleave uses directly. Order is fixed on
  # purpose (row 2.2, row 2.16): abort check, THEN the lease heartbeat, THEN
  # reclaim - never the reverse, and never a write of any kind before the
  # abort check has cleared.
  def run(context, runner: Worktree::ShellRunner.new, skip: [], now: Time.now, heartbeat: Lock.method(:heartbeat))
    abort_result = abort_if_merging(context, runner: runner)
    unless abort_result[:ok]
      return {
        ok: false, aborted: true, error: abort_result[:error],
        recovery_command: abort_result[:recovery_command], reclaimed: [], extended: [],
      }
    end

    session = context&.session
    heartbeat.call(context.intent_dir, session: session, now: now) unless blank?(session)

    result = reclaim(context, runner: runner, skip: skip, now: now)
    {
      ok: true, aborted: false, error: nil, recovery_command: nil,
      reclaimed: result[:reclaimed], extended: result[:extended],
    }
  end

  # --- internals ---------------------------------------------------------------

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
  private_class_method :blank?

  def savepoint_path(intent_dir)
    File.join(intent_dir.to_s, "savepoint.md")
  end
  private_class_method :savepoint_path

  def savepoint_content(intent_dir)
    path = savepoint_path(intent_dir)
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :savepoint_content

  # The node's own worktree branch (n3's naming: `plastic/<id>--<slug>--<node>`),
  # derived from the intent id/slug alone - never through NodeWorktree, which
  # this node does not depend on.
  def node_branch(context, node)
    "plastic/#{context.intent_id}--#{context.intent_slug}--#{node}"
  end
  private_class_method :node_branch

  # [head_sha, committer_time] for `branch` in `worktree`'s repo, or [nil, nil]
  # when the worktree is gone, the branch does not exist, or anything else
  # about the git call fails (row 2.13: never raise).
  def branch_head(runner, worktree, branch)
    return [nil, nil] if blank?(worktree) || blank?(branch)

    res = runner.run("-C", worktree, "log", "-1", "--format=%H%x1f%cI", branch)
    return [nil, nil] unless res.success?

    sha, iso = res.stdout.to_s.strip.split("\x1f")
    [sha, parse_time(iso)]
  rescue StandardError
    [nil, nil]
  end
  private_class_method :branch_head

  def parse_time(raw)
    return nil if blank?(raw)

    Time.iso8601(raw.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :parse_time

  # Row 2.18: the attempt number comes from the ledger's own count of
  # `running` lines since the subject's last terminal line - the exact same
  # arithmetic NodeInput uses to name that attempt's packet file, so the
  # extensions file for a `running` line always matches the packet it extends.
  def current_attempt(entries, subject)
    ReadySet.attempts_count(entries, subject)
  end
  private_class_method :current_attempt

  def extensions_path(intent_dir, node, attempt)
    File.join(intent_dir.to_s, "attempts", "#{node}--a#{attempt}.extensions")
  end
  private_class_method :extensions_path

  # Row 2.8: counted from the attempt-scoped file alone, so a prior attempt's
  # extensions never count against a fresh dispatch.
  def extension_count(intent_dir, node, attempt)
    path = extensions_path(intent_dir, node, attempt)
    return 0 unless File.exist?(path)

    File.read(path).each_line.count { |l| !l.strip.empty? }
  end
  private_class_method :extension_count

  # Row 2.9: the observed head sha and the time, one line, append-only.
  def record_extension(intent_dir, node, attempt, head_sha, now)
    path = extensions_path(intent_dir, node, attempt)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "a") { |f| f.write("#{now.utc.iso8601}  head=#{head_sha}\n") }
  end
  private_class_method :record_extension
end
