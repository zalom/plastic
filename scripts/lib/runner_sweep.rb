# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "fileutils"
require_relative "worktree"
require_relative "lock"
require_relative "node_ledger"
require_relative "ready_set"
require_relative "savepoint"

# RunnerSweep (intent 340, G7, n2): the first thing every `step` does. The
# single entry point is #reclaim, plus #run, which composes it with the
# delivery-lease heartbeat for a caller that has no absorb step to interleave.
# `step` (a later node) runs absorb, then calls #reclaim itself, so a
# reclaimed node's just-landed work from absorb is never thrown away by a
# stale read (matrix row 2.20).
#
# Owner ruling 2026-09-24 (intent 390 part B): Plastic runs no version
# control command. #abort_if_merging (a `git rev-parse MERGE_HEAD` check) is
# gone outright: Plastic never runs a merge itself anymore (NodeWorktree.merge
# prints the instruction instead), so there is no merge of Plastic's own that
# could be left half-finished for a later step to trip on.
#
# #reclaim walks every node whose CURRENT status (the ledger's own resolution,
# never a raw scan) is `running`, skipping anything named in `skip:` (the
# nodes this step already absorbed, row 2.19) or already terminal (a `done`
# node is never touched, row 2.12 - it simply never shows up as `running`).
# Freshness used to come from the node branch's own git commit time; with git
# gone, it now comes from the node's own worktree files: an expired lease
# whose worktree directory carries no file modified after the expiry is
# reclaimed outright. An expired lease whose worktree DOES carry a file newer
# than its expiry is extended instead, up to twice per attempt (row 2.7); the
# extension is never a ledger transition (`running` cannot re-enter `running`
# under the transition layer), so it is one line appended to
# attempts/<node>--a<N>.extensions, `N` derived from the ledger's own attempt
# count (row 2.18), never trusted from the caller. A third expiry reclaims
# regardless of newer files. A node whose worktree cannot be resolved at all
# (no repo, no path) has nothing to check freshness against and is reclaimed
# on its first expiry, same as before this change for an unresolvable branch.
#
# Pure and dependency-injected: the delivery-lease heartbeat goes through an
# injected `heartbeat:` (default Lock.heartbeat) so ordering (row 2.16) is
# provable without a real lock file. No eval, no ENV/global-constant seam, no
# git call anywhere in this file.
module RunnerSweep
  module_function

  # D-ish: at most two extensions per attempt (row 2.7); the third expiry
  # reclaims regardless of newer files.
  MAX_EXTENSIONS_PER_ATTEMPT = 2

  # reclaim(context, skip:, now:) -> {reclaimed: [{node:, holder:,
  # expired:}], extended: [{node:, head:, time:}]}. Reads the ledger fresh on
  # every call (no cache), which is what makes calling it AFTER absorb (row
  # 2.20) actually see absorb's own just-landed work rather than a stale
  # snapshot taken before it.
  def reclaim(context, skip: [], now: Time.now)
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
      worktree_path = node_worktree_path(context, subject)
      newest_mtime = newest_file_mtime(worktree_path)
      has_new_commits = newest_mtime && newest_mtime > expires_at

      if has_new_commits
        attempt = current_attempt(entries, subject)
        count = extension_count(intent_dir, subject, attempt)
        if count < MAX_EXTENSIONS_PER_ATTEMPT
          record_extension(intent_dir, subject, attempt, newest_mtime, now)
          extended << { node: subject, mtime: newest_mtime.utc.iso8601, time: now.utc.iso8601 }
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

  # run(context, skip:, now:, heartbeat:) -> the composed report a caller
  # with no absorb step to interleave uses directly. Order is fixed on
  # purpose (row 2.16): the lease heartbeat, THEN reclaim - never a write of
  # any kind before the heartbeat lands.
  def run(context, skip: [], now: Time.now, heartbeat: Lock.method(:heartbeat))
    session = context&.session
    heartbeat.call(context.intent_dir, session: session, now: now) unless blank?(session)

    result = reclaim(context, skip: skip, now: now)
    { ok: true, aborted: false, error: nil, recovery_command: nil,
      reclaimed: result[:reclaimed], extended: result[:extended] }
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

  # The node's own worktree path (n3's naming:
  # `<repo>/.claude/worktrees/<id>--<slug>--<node>`), derived from the intent
  # id/slug alone - never through NodeWorktree, which this module does not
  # depend on. nil when the intent has no code worktree to derive from.
  def node_worktree_path(context, node)
    repo = repo_root(context)
    return nil if repo.nil?

    File.join(repo, ".claude", "worktrees", "#{context.intent_id}--#{context.intent_slug}--#{node}")
  end
  private_class_method :node_worktree_path

  # Three levels up from `context.worktree` is the repo root (Worktree.paths'
  # own shape); nil when there is no code worktree at all.
  def repo_root(context)
    wt = context&.worktree
    return nil if blank?(wt)

    File.dirname(File.dirname(File.dirname(File.expand_path(wt))))
  end
  private_class_method :repo_root

  # The most recent mtime among every file under `dir` (recursively), or nil
  # when the directory does not exist or is empty (row 2.13: never raise) -
  # the file-system replacement for a git branch's own committer time, since
  # Plastic reads no git history anymore.
  def newest_file_mtime(dir)
    return nil if blank?(dir) || !Dir.exist?(dir)

    Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
       .reject { |f| File.directory?(f) }
       .map { |f| File.mtime(f) }
       .max
  rescue StandardError
    nil
  end
  private_class_method :newest_file_mtime

  def parse_time(raw)
    return nil if blank?(raw)

    Time.iso8601(raw.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :parse_time

  # Row 2.18: the attempt number comes from the ledger's own count of
  # `running` lines since the subject's last terminal line - the exact same
  # arithmetic NodeInput uses to name that attempt's input file, so the
  # extensions file for a `running` line always matches the node input it extends.
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

  # Row 2.9: the observed newest file mtime and the time, one line, append-only.
  def record_extension(intent_dir, node, attempt, newest_mtime, now)
    path = extensions_path(intent_dir, node, attempt)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "a") { |f| f.write("#{now.utc.iso8601}  mtime=#{newest_mtime.utc.iso8601}\n") }
  end
  private_class_method :record_extension
end
