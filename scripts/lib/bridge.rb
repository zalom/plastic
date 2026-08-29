#!/usr/bin/env ruby
# encoding: UTF-8

require "json"
require "yaml"
require "fileutils"
require "tempfile"
require "digest"
require "socket"
require_relative "worktree"
require_relative "lock"
require_relative "spec_header"

module Bridge
  STAGES = %w[what why how exec done].freeze

  # Placeholder sentinel (intent 60b). A scaffolded lifecycle file
  # (spec.md/plan.md/checklist.md/outcome.md) carries this exact string as its
  # first line until an agent fills the file and deletes the sentinel. The
  # sentinel is the "stage not reached yet" marker, so stage detection treats a
  # sentinel-marked file as absent (see stage_file_present?). The intent file
  # (<id>--<slug>.md) is never sentineled; it is born complete.
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"

  # Single place a skill-reference string gets built (intent 201, D3): every
  # message that used to write "/plastic-something" by hand calls this
  # instead, so a fourth harness only teaches ITS prefix once instead of
  # hunting the codebase for hardcoded slashes. The actual prefix table lives
  # on Lock (see lock.rb), which bridge.rb already requires; this is a thin
  # delegator so every call site in this file reads Bridge.skill_ref.
  def self.skill_ref(name, harness: :claude)
    Lock.skill_ref(name, harness: harness)
  end

  # Bridge cleanup is terminal-state, not age-based (intent 80). A bridge is dead
  # weight ONLY once its intent is terminal (no longer in its store's INDEX.md
  # `## Active` block); such bridges are purged. An Active intent's bridge is kept
  # unconditionally, because while the intent is live the bridge is still load-
  # bearing: it is the continuation signal (a parked or interrupted run resumes
  # from it) and the anti-collision lock for parallel deliveries on one store,
  # keeping each session's gate checks and locks from overwriting another's. An
  # age window was the wrong
  # axis: it left dead bridges resident for ~2 days AND could reap bridges of
  # interrupted-but-still-active intents, which are exactly the ones to preserve.

  def self.intent_file(intent_dir)
    dir_name = File.basename(intent_dir)
    "#{intent_dir}/#{dir_name}.md"
  end

  # Single source for the OS temp location holding bridge files. Lets every
  # process (arm_auto, the gate hooks) agree, and lets tests fully isolate by
  # pointing PLASTIC_TMP at a Dir.mktmpdir. This is OS-temp-location resolution,
  # not a logic-config injection seam.
  def self.tmp_dir
    t = ENV["PLASTIC_TMP"]
    (t.nil? || t.strip.empty?) ? "/tmp" : t
  end

  # Per-intent bridge key (intent 131): `plastic-<session>--<intent_id>.json`
  # when intent_id is present, else the legacy single-key
  # `plastic-<session>.json`. The per-intent key is what lets two concurrent
  # deliveries under ONE session id keep separate bridge files instead of
  # clobbering a shared one; the legacy form is still produced (and read) when
  # no intent_id is given, so old single-key files stay valid.
  def self.path(session, intent_id: nil, tmp: tmp_dir)
    if blank?(intent_id)
      "#{tmp}/plastic-#{session}.json"
    else
      "#{tmp}/plastic-#{session}--#{intent_id}.json"
    end
  end

  # --- Session resolution (intent 52) ----------------------------------------

  def self.blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # Raised by arm when the delivery lock cannot be acquired (held elsewhere,
  # stale, excluded, or corrupt). The message names the resolving command.
  class LockHeldError < StandardError; end

  # The absolute intent dir a bridge points at, or nil.
  def self.bridge_intent_dir(bridge_data)
    return nil unless bridge_data.is_a?(Hash)
    info = bridge_data["intent"] || {}
    store = info["store"]
    dir = info["dir"]
    (store && dir) ? File.expand_path("#{store}/#{dir}") : nil
  end

  # Bridge-cache copy of the durable lock file's fields (D2: the bridge is a
  # CACHE; the file is the truth). Never carries a pid.
  def self.lock_cache(lock_data)
    {
      "owner_session" => lock_data["owner_session"],
      "acquired_at" => lock_data["acquired_at"],
      "host" => lock_data["host"],
      "type" => lock_data["type"],
      "delegates" => Array(lock_data["delegates"]),
      "owner_harness" => lock_data["owner_harness"],
      "owner_agent" => lock_data["owner_agent"],
      "owner_model" => lock_data["owner_model"],
      "owner_thread" => lock_data["owner_thread"],
      "run_mode" => lock_data["run_mode"],
      "delegate_activity" => Array(lock_data["delegate_activity"]),
    }
  end

  # Deterministic, session-id-less bridge key derived from store + intent id.
  # Stable across processes so a session-less arm and a later session-less
  # gate-check resolve to the same bridge file.
  def self.derive_key(store, intent_id)
    "auto-" + Digest::SHA256.hexdigest("#{store}/#{intent_id}")[0, 10]
  end

  # Resolve a bridge session: first non-empty of explicit (the stdin session_id),
  # CLAUDE_CODE_SESSION_ID, then a derived key. Never returns nil/empty.
  # Whitespace-only counts as empty.
  #
  # The CLAUDE_CODE_SESSION_ID fallback (intent 79) carries the bg/headless real
  # session id (Claude Code passes session_id on stdin, not via an env var; the
  # headless id lives in CLAUDE_CODE_SESSION_ID). Keying by the real id (instead of
  # a derived hash) lets the gate hooks, which receive that same id on stdin, find
  # the bridge by direct filename lookup.
  def self.resolve_session(explicit, intent_id:, store:)
    return explicit.to_s.strip unless blank?(explicit)
    code_env = ENV["CLAUDE_CODE_SESSION_ID"]
    return code_env.to_s.strip unless blank?(code_env)
    derive_key(store, intent_id)
  end

  # Walk up from file_path; return the first ancestor that looks like an intent
  # directory (`.../store/<id>--<slug>`), else nil. Used to derive the savepoint
  # target without needing a bridge. The input is always a file inside the intent
  # dir (never the dir itself), so the walk-up starts at its parent.
  def self.intent_dir_for(file_path)
    dir = File.expand_path(file_path)
    loop do
      parent = File.dirname(dir)
      break if parent == dir # reached filesystem root
      dir = parent
      return dir if dir.match?(%r{/store/[^/]+--[^/]+\z})
    end
    nil
  end

  # A bridge hash is usable iff it has a non-empty session and an intent Hash.
  def self.bridge_valid?(data)
    data.is_a?(Hash) && !blank?(data["session"]) && data["intent"].is_a?(Hash)
  end

  # Tiered cwd discriminator for one bridge candidate (intent 131). A session
  # now owns SEVERAL bridges (one per concurrent intent), so the discriminator
  # that used to be "cwd overlaps intent.store" is too coarse: every sibling
  # under the same store shares it. worktree.code is the only field that
  # differs between siblings, so it is the strongest signal; the intent dir is
  # next; the shared store is a last-resort coarse tie.
  #   2 - cwd is the intent's provisioned code worktree (or under it)
  #   1 - cwd is the intent's own dir (or under it)
  #   0 - cwd merely overlaps the intent's store (shared by every sibling)
  #  -1 - no signal at all
  def self.bridge_cwd_tier(data, cwd_abs)
    worktree_code = data.dig("worktree", "code")
    if !blank?(worktree_code)
      wc_abs = File.expand_path(worktree_code)
      return 2 if cwd_abs == wc_abs || cwd_abs.start_with?("#{wc_abs}/")
    end

    dir_abs = bridge_intent_dir(data)
    if dir_abs
      return 1 if cwd_abs == dir_abs || cwd_abs.start_with?("#{dir_abs}/")
    end

    store = data.dig("intent", "store").to_s
    unless store.empty?
      store_abs = File.expand_path(store)
      return 0 if cwd_abs == store_abs || cwd_abs.start_with?("#{store_abs}/") ||
                  store_abs.start_with?("#{cwd_abs}/")
    end

    -1
  end

  # The provisioned code worktree dir (<repo>/.claude/worktrees/{id}--{slug})
  # that contains file_path, or nil (intent 168). Structural and bridge-free:
  # Worktree.provision builds exactly this layout, so a file under it is
  # "worktree-scoped" and only that intent may gate it. The {id}--{slug} shape
  # (a `--` in the dir name) is required, so a stray .claude/worktrees/README
  # is not worktree-scoped and returns nil.
  def self.enclosing_worktree_dir(file_path)
    return nil if blank?(file_path)
    m = File.expand_path(file_path).match(%r{\A(.*/\.claude/worktrees/[^/]+--[^/]+)(?:/|\z)})
    m && m[1]
  end

  # Resolve the active bridge: scan tmp for plastic-*.json (both per-intent and
  # legacy-keyed files), keep only valid bridges, filter to the caller's own
  # session when it has one, prefer auto-armed, then disambiguate by cwd tier
  # (see bridge_cwd_tier), tie-break by newest mtime. No exact-session fast
  # path: a session now legitimately owns several bridges (one per concurrent
  # intent), so filename lookup alone cannot pick the right one; cwd must
  # decide (intent 131).
  def self.discover_bridge(session:, cwd: Dir.pwd, tmp: tmp_dir, edited_path: nil)
    candidates = Dir.glob(File.join(tmp, "plastic-*.json")).reject { |f| f.end_with?(".tmp") }
    parsed = candidates.filter_map do |f|
      data = (JSON.parse(File.read(f)) rescue nil)
      next unless data && bridge_valid?(data)
      { file: f, data: data, mtime: File.mtime(f) }
    end
    return nil if parsed.empty?

    # Worktree-membership-first (intent 168). A caller may pass the edited
    # file as edited_path; when that file lies inside a provisioned code worktree
    # (<repo>/.claude/worktrees/{id}--{slug}), only that worktree's owning intent
    # may gate the write, BEFORE the intent-90 per-session filter below. Resolve
    # the candidate whose worktree.code owns that dir (newest mtime on a tie), or
    # nil when none owns it, so a session-keyed guided bridge can never claim a
    # write located inside a sibling intent's worktree. No edited_path (every
    # other caller) or a non-worktree path skips this and runs the pipeline
    # unchanged (intents 90/52/131 preserved).
    unless blank?(edited_path)
      wt_dir = enclosing_worktree_dir(edited_path)
      if wt_dir
        owners = parsed.select do |c|
          code = c[:data].dig("worktree", "code")
          !blank?(code) && File.expand_path(code) == wt_dir
        end
        return owners.max_by { |c| c[:mtime] }&.fetch(:data)
      end
    end

    has_session = !blank?(session)

    # Strict per-session ownership (intent 90): when the caller HAS a session, a foreign
    # session's bridge is NEVER a valid resolution. Own-session and the derived-key case both
    # reduce to candidate["session"] == session (the derived key IS the session that armed the
    # bridge). A caller that owns no bridge resolves to nil, so its gates fail open instead of
    # inheriting another session's armed intent.
    #
    # When the caller has NO session (truly headless, intent 52), keep the legacy degraded
    # selection below so a single armed derived-key bridge is still discoverable - the hook
    # cannot know the session there, and a lone armed intent must still gate.
    if has_session
      parsed = parsed.select { |c| c[:data]["session"].to_s == session.to_s }
      return nil if parsed.empty?
    end

    # Auto-preference pool: a build-armed bridge is preferred over a merely
    # derived one, but ONLY as a fallback when cwd cannot decide (below). cwd
    # must win over auto-preference, so this pool is not applied before the
    # cwd tiering (intent 131: a guided sibling in the caller's own worktree
    # must beat an auto sibling in another worktree).
    auto = parsed.select { |c| c[:data].dig("build", "auto") == true }
    auto_pool = auto.empty? ? parsed : auto

    unless blank?(cwd)
      cwd_abs = File.expand_path(cwd)
      # Tier the FULL session pool by cwd BEFORE the auto-preference filter.
      # When cwd overlaps ANY candidate (tier >= 0) it decides outright, even
      # against a newer or auto-armed sibling: worktree.code (tier 2) and the
      # intent dir (tier 1) disambiguate same-store siblings (intent 131), and
      # a store overlap (tier 0) still selects the overlapping bridge over an
      # off-cwd one in another store (the intent 90/52 store filter, preserved).
      # Only when NO candidate overlaps cwd (max tier -1) do we fall through to
      # the auto-preference pool and newest mtime, so a lone armed bridge
      # off-cwd still resolves (intent 52 headless).
      tiered = parsed.map { |c| [bridge_cwd_tier(c[:data], cwd_abs), c] }
      max_tier = tiered.map(&:first).max
      if max_tier && max_tier >= 0
        winners = tiered.select { |tier, _| tier == max_tier }.map { |_, c| c }
        return winners.max_by { |c| c[:mtime] }&.fetch(:data)
      end
    end

    auto_pool.max_by { |c| c[:mtime] }&.fetch(:data)
  end

  # --- Shared INDEX entry matcher (intent 188, D12/D13) -----------------------
  #
  # ONE definition site for the "- [ID <sep> Title](link)" shape both
  # `intent_active?` (below) and `scripts/end-intent`'s own INDEX-move parser
  # depend on, so the two regexes can never drift apart again (the em-dash-only
  # bug was flagged and deferred at intents 96 and 169, then independently
  # rediscovered as a SEPARATE end-intent defect at intent 188). Accepts a real
  # em dash (U+2014) OR a plain hyphen as the id/title separator on READ.
  # Hardening this widens intent_active?'s fail-open case: a hyphen-formatted
  # `## Active` line used to read as not-active (lock gate failed open); it now
  # reads as active (gate correctly blocks). Accepted as a bug fix (D13): no
  # passing test relied on the old fail-open behavior. Every WRITE still emits
  # the real em dash (D10); only what this matcher can PARSE has widened.
  #
  # The separator is built from the codepoint, not a literal byte in this
  # source file, so this new code stays em-dash free (the shipped-file
  # convention; store files like INDEX.md are the exempt surface this matcher
  # READS, not where this constant lives). Matches the existing convention in
  # scripts/end-intent.
  EM_DASH = "\u2014".freeze
  INDEX_ENTRY_RE = /\A- \[(\S+)\s+(?:#{Regexp.escape(EM_DASH)}|-)\s+(.*?)\]\(([^)]+)\)/.freeze

  # Match `line` (already chomped) against the shared INDEX entry shape.
  # Returns a MatchData (captures: 1 = id, 2 = title, 3 = link) or nil.
  def self.index_entry_match(line)
    line.to_s.match(INDEX_ENTRY_RE)
  end

  # --- Terminal-state bridge purge (intent 80) -------------------------------

  # True iff the intent is Active in its store's INDEX.md. An INDEX.md lives at
  # the PARENT of the store/ dir the bridge records, so we resolve it from the
  # bridge's intent.store. Non-raising: any failure (missing/unreadable INDEX,
  # bad arg) returns false, which means "not active" so the caller treats the
  # bridge as purgeable. `index_active_ids` is a pure-data test seam: when an
  # Array of id strings is supplied, membership is checked against it directly
  # with no file read.
  def self.intent_active?(intent_id, store:, index_active_ids: nil)
    target = intent_id.to_s
    return index_active_ids.include?(target) if index_active_ids.is_a?(Array)

    index = File.join(File.dirname(store.to_s), "INDEX.md")
    return false unless File.exist?(index)

    in_active = false
    File.foreach(index) do |line|
      stripped = line.chomp
      if stripped == "## Active"
        in_active = true
        next
      end
      next unless in_active
      break if stripped.start_with?("## ") # next section ends the Active block
      m = index_entry_match(stripped)
      return true if m && m[1] == target
    end
    false
  rescue StandardError
    false
  end

  # Remove tmp/plastic-*.json bridge files whose intent is terminal, so
  # discover_bridge's per-fire scan stays bounded. Best-effort and non-raising:
  # returns the array of removed paths. A bridge is purged when it cannot be
  # parsed, has no intent.id, has no intent.store, or its intent is not Active in
  # its store's INDEX.md. An Active intent's bridge is kept (continuation signal +
  # anti-collision lock), and the current session's own bridge is never purged
  # (preserves the disarm_auto contract that it stays readable). Wired into
  # arm_auto and disarm_auto so both manual and auto delivery keep the temp dir
  # clean at deterministic work boundaries.
  def self.purge_done_bridges(session:, tmp: tmp_dir)
    # Own-bridge predicate (intent 131): a session now legitimately owns
    # SEVERAL bridges (one per concurrent intent), so "current" is no longer
    # one filename. Skip the legacy single-key file for this session AND every
    # per-intent-keyed file for this session; none of the session's own live
    # bridges may be reaped mid-run.
    own_legacy_name = File.basename(path(session, tmp: tmp))
    own_prefix = "plastic-#{session}--"
    removed = []
    Dir.glob(File.join(tmp, "plastic-*.json")).each do |f|
      next if File.basename(f) == own_legacy_name || File.basename(f).start_with?(own_prefix)
      begin
        data = JSON.parse(File.read(f)) rescue nil
        keep = false
        if data
          id = data.dig("intent", "id")
          store = data.dig("intent", "store")
          keep = !blank?(id) && !blank?(store) && intent_active?(id, store: store)
          # Never purge a bridge whose intent still holds a delivery lock
          # (intent 108, D6): the End tail clears the lock BEFORE the bridge
          # becomes purge-eligible, so a held lock means the tail is not done.
          unless keep
            dir = bridge_intent_dir(data)
            keep = !dir.nil? && File.exist?(Lock.path(dir))
          end
        end
        next if keep
        File.delete(f)
        removed << f
      rescue Errno::ENOENT
        # Raced with another job that already removed it; count as purged.
        removed << f
      rescue => e
        $stderr.puts "plastic: purge skipped #{f}: #{e.message}"
      end
    end
    removed
  rescue => e
    $stderr.puts "plastic: purge_done_bridges failed: #{e.message}"
    removed || []
  end

  # Try the per-intent path first; when it is absent and an intent_id was
  # given, fall back to the legacy single-key path (migration + legacy
  # tolerance, intent 131): a live `plastic-<session>.json` from before this
  # intent keeps resolving during the transition. The legacy fallback is
  # honored for a specific intent_id ONLY when the legacy file actually carries
  # that intent (or carries none), so a caller asking for intent A never acts
  # on a legacy file that still holds sibling B.
  def self.read(session, intent_id: nil, tmp: tmp_dir)
    p = path(session, intent_id: intent_id, tmp: tmp)
    return JSON.parse(File.read(p)) if File.exist?(p)
    return nil if blank?(intent_id)
    legacy = path(session, tmp: tmp)
    return nil unless File.exist?(legacy)
    data = JSON.parse(File.read(legacy))
    id = data.is_a?(Hash) ? data.dig("intent", "id") : nil
    (blank?(id) || id.to_s == intent_id.to_s) ? data : nil
  rescue JSON::ParserError
    nil
  end

  # Self-keying (intent 131): the file `write` targets is derived from
  # `data.dig("intent", "id")`, not a caller-supplied intent_id, so every
  # existing `write(session, data)` call site keys itself correctly for free
  # as long as `data["intent"]["id"]` is set (arm/derive/disarm_auto/
  # repair_lock/hook-gate-check/plastic-lock all carry it).
  def self.write(session, data, tmp: tmp_dir)
    raise ArgumentError, "bridge session must be present" if blank?(session)
    intent_id = data.is_a?(Hash) ? data.dig("intent", "id") : nil
    p = path(session, intent_id: intent_id, tmp: tmp)
    # Atomic write: tmp file + rename to prevent partial reads
    tmp_file = "#{p}.tmp.#{Process.pid}"
    File.write(tmp_file, JSON.pretty_generate(data.merge("updated_at" => Time.now.utc.iso8601)))
    File.rename(tmp_file, p)
  rescue => e
    File.delete(tmp_file) if tmp_file && File.exist?(tmp_file)
    raise e
  end

  # True iff a lifecycle file is PRESENT AND REAL: it exists and its first line is
  # not the placeholder sentinel. Reads only the file head (never the whole file)
  # so the dashboard stays fast across many intents. Exact first-line match only,
  # so a real file that merely contains an HTML comment later is unaffected, and a
  # partially-edited sentinel reads as real rather than sticking as a placeholder.
  def self.stage_file_present?(path)
    return false unless File.exist?(path)
    first = File.open(path, &:gets)
    return true if first.nil? # empty file: present, not a sentinel
    first.chomp != PLACEHOLDER_SENTINEL
  rescue StandardError
    File.exist?(path)
  end

  # True iff actions/ holds AT LEAST ONE real action file: a non-empty *.md whose
  # first line is not the placeholder sentinel. A `.gitkeep` (no .md extension)
  # never counts, an empty *.md never counts, and a sentinel-only *.md never
  # counts. Pure and side-effect-free so the gate stays unit-testable. Fail-open:
  # a missing actions/ dir globs to nothing and returns false (the gate then
  # reports it needs a real action file); it never raises.
  def self.has_real_action?(intent_dir)
    Dir.glob("#{intent_dir}/actions/*.md").any? do |f|
      File.file?(f) && File.size(f) > 0 && stage_file_present?(f)
    end
  rescue StandardError
    false
  end

  def self.derive_stage(intent_dir)
    return "done" if stage_file_present?("#{intent_dir}/outcome.md")
    if stage_file_present?("#{intent_dir}/plan.md") &&
       has_real_action?(intent_dir) &&
       stage_file_present?("#{intent_dir}/checklist.md")
      return "exec"
    end
    return "how" if stage_file_present?("#{intent_dir}/spec.md")
    return "why" if File.exist?(intent_file(intent_dir))
    "what"
  end

  def self.has_files(intent_dir)
    files = []
    ifile = File.basename(intent_file(intent_dir))
    files << ifile if File.exist?("#{intent_dir}/#{ifile}")
    ["spec.md", "plan.md", "checklist.md", "outcome.md"].each do |f|
      files << f if stage_file_present?("#{intent_dir}/#{f}")
    end
    files << "actions/" if has_real_action?(intent_dir)
    files
  end

  def self.missing_for_stage(stage, intent_dir = nil)
    ifile = intent_dir ? File.basename(intent_file(intent_dir)) : "intent.md"
    case stage
    when "what" then [ifile]
    when "why" then ["spec.md"]
    when "how" then ["plan.md", "actions/", "checklist.md"]
    when "exec" then ["outcome.md"]
    else []
    end
  end

  # --- Cycle-step savepoint ledger (intent 34) ------------------------------
  #
  # savepoint.md is a deterministic, append-only, one-line-per-milestone ledger
  # (newest at the bottom). It is sugar on top of the conventions: derived from
  # files-on-disk, rebuildable, never a source of truth. Milestones are
  # file-event boundaries only; action/resource files record nothing.

  SAVEPOINT_FILE = "savepoint.md"

  # Map a written filename to [stage_label, milestone_text], or nil if the file
  # is not a lifecycle milestone.
  def self.savepoint_milestone(intent_dir, basename)
    return ["What", basename] if basename == File.basename(intent_file(intent_dir))

    case basename
    when "spec.md"      then ["Why", "spec.md created"]
    when "plan.md"      then ["How", "plan.md created"]
    when "checklist.md" then ["How", "checklist.md created"]
    when "outcome.md"   then ["Exec", "outcome.md created"]
    end
  end

  # Milestones already recorded in the ledger (field 3 of each line).
  def self.savepoint_recorded_milestones(intent_dir)
    f = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(f)
    File.read(f).each_line.map do |line|
      parts = line.strip.split(/\s{2,}/)
      parts.length >= 3 ? parts[2] : nil
    end.compact
  end

  # (stage, milestone) pairs already recorded in the ledger. The pair (not the
  # milestone text alone) is the dedup key, because state-from-ledger lines like
  # `Why  started` and `How  started` share the milestone text "started" while
  # being distinct events (intent 81).
  def self.savepoint_recorded_pairs(intent_dir)
    f = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(f)
    File.read(f).each_line.filter_map do |line|
      parts = line.strip.split(/\s{2,}/)
      parts.length >= 3 ? [parts[1], parts[2]] : nil
    end
  end

  # Append one ledger line for (stage, milestone) unless that pair is already
  # recorded. The single append primitive shared by every line class. Returns
  # true when a line was written, false when it was a no-op.
  def self.append_savepoint_line(intent_dir, stage, milestone, now)
    return false if savepoint_recorded_pairs(intent_dir).include?([stage, milestone])
    line = "#{now.utc.iso8601}  #{stage}  #{milestone}\n"
    File.open(File.join(intent_dir, SAVEPOINT_FILE), "a") { |io| io.write(line) }
    true
  end

  # Append the artifact-landing milestone for file_path if (and only if) it is a
  # milestone not already recorded. Returns true when a line was written.
  def self.append_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_milestone(intent_dir, basename)
    return false unless milestone
    # A sentinel-marked lifecycle file logs NO milestone (the stage is not real
    # yet). The intent file is never sentineled, so it still logs its What line.
    return false unless stage_file_present?(File.join(intent_dir, basename))

    append_savepoint_line(intent_dir, stage, milestone, now)
  end

  # --- State-from-ledger: pre-stage, exec-start, and terminal lines (81) ------
  #
  # On top of intent 34's artifact-landing milestones, the ledger gains:
  #   - `started` lines, one per cycle stage entry (pre-stage, written by the
  #     PreToolUse savepoint hook the moment a stage's artifact is first written);
  #   - an `Exec  started` companion emitted when checklist.md lands;
  #   - a terminal `Done  delivered|abandoned` line written by the completion path.
  # None of these are derivable from files on disk, so they are deliberately NOT
  # part of savepoint_milestone and are never regenerated by rebuild_savepoint:
  # a rebuilt ledger is the file-landing skeleton, the live ledger is richer.

  # Map a written filename to the [stage, "started"] pre-stage milestone, or nil.
  # spec.md => entering Why, plan.md => entering How. checklist.md/outcome.md do
  # not open a stage (checklist's Exec-start is the append_exec_started companion).
  def self.savepoint_started_milestone(basename)
    case basename
    when "spec.md" then ["Why", "started"]
    when "plan.md" then ["How", "started"]
    end
  end

  # Append the pre-stage `started` line for file_path, iff: the basename opens a
  # stage, the stage is genuinely starting (its artifact is not yet a REAL file,
  # so a sentinel placeholder still counts as "starting"), and the pair is not
  # already recorded. Returns true when a line was written.
  def self.append_started_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_started_milestone(basename)
    return false unless milestone
    return false if stage_file_present?(File.join(intent_dir, basename))

    append_savepoint_line(intent_dir, stage, milestone, now)
  end

  # Append the `Exec  started` companion (emitted when checklist.md lands, in the
  # same PostToolUse event as the `How  checklist.md created` line). Idempotent.
  def self.append_exec_started(intent_dir, now: Time.now)
    append_savepoint_line(intent_dir, "Exec", "started", now)
  end

  TERMINAL_DISPOSITIONS = %w[delivered abandoned].freeze

  # Append the terminal bookend `Done  delivered|abandoned`, written by the
  # completion path when an intent transfers to INDEX's Completed/Abandoned
  # section. Idempotent per disposition. Raises on an unknown disposition.
  def self.append_terminal_savepoint(intent_dir, disposition, now: Time.now)
    unless TERMINAL_DISPOSITIONS.include?(disposition)
      raise ArgumentError,
            "disposition must be one of #{TERMINAL_DISPOSITIONS.join(', ')}, got #{disposition.inspect}"
    end

    append_savepoint_line(intent_dir, "Done", disposition, now)
  end

  # --- Tier convenience line (intent 130, D-A) ------------------------------
  #
  # spec.md's top `Tier: S|M|L` line is the single authoritative record of an
  # intent's proportional-auto-sizing tier (see PLASTIC.md `## Tiers`). This
  # reads that line only; it never validates or enforces it (convention-only,
  # matching the skill and agent contracts). Returns nil when spec.md is
  # absent, empty, or its first line does not match, so a missing/malformed
  # Tier line changes nothing about existing rebuild behavior.
  # The grammar itself now lives in SpecHeader (scripts/lib/spec_header.rb, intent 213);
  # this method is a thin read on top of it.
  def self.savepoint_tier(intent_dir)
    SpecHeader.parse_file(File.join(intent_dir, "spec.md"))[:tier]
  end

  # Reconstruct the ledger from files on disk (timestamps from mtimes), in
  # stage order, overwriting savepoint.md. Returns the number of lines written.
  # When spec.md carries a Tier line, one convenience `Tier  <value>` line is
  # echoed right after the spec.md milestone line (same mtime), so the tier
  # survives a rebuild without becoming a new source of truth.
  def self.rebuild_savepoint(intent_dir)
    ordered = [
      File.basename(intent_file(intent_dir)),
      "spec.md", "plan.md", "checklist.md", "outcome.md",
    ]
    lines = ordered.flat_map do |basename|
      path = File.join(intent_dir, basename)
      next [] unless stage_file_present?(path)
      stage, milestone = savepoint_milestone(intent_dir, basename)
      next [] unless milestone
      stamp = File.mtime(path).utc.iso8601
      entry = "#{stamp}  #{stage}  #{milestone}\n"
      if basename == "spec.md" && (tier = savepoint_tier(intent_dir))
        [entry, "#{stamp}  Tier  #{tier}\n"]
      else
        [entry]
      end
    end
    File.write(File.join(intent_dir, SAVEPOINT_FILE), lines.join)
    lines.length
  end

  # --- Phantom-line detection (intent 134) ------------------------------------
  #
  # A companion to the ledger, not a new writer: pure, disk-only, hermetic (no bridge or
  # session resolution, no writes), matching intent 52's savepoint-decoupling precedent. Under
  # a gate-routing misfire (bug 131) or an out-of-band merge (124a's precedent), a ledger line
  # can go stale or duplicate without the file evidence agreeing. This detects, never repairs;
  # repair is `rebuild_savepoint` (live intents) or the 124a manual Done-bookend recipe
  # (terminal intents, human-granted only).

  # (stage, milestone) -> basename, for every file-landing milestone this intent_dir could have
  # produced (the intent file plus the four lifecycle artifacts). Reuses savepoint_milestone so
  # the mapping never drifts from the one the writer itself uses.
  def self.savepoint_file_landing_pairs(intent_dir)
    basenames = [File.basename(intent_file(intent_dir)), "spec.md", "plan.md", "checklist.md", "outcome.md"]
    basenames.each_with_object({}) do |basename, map|
      pair = savepoint_milestone(intent_dir, basename)
      map[pair] = basename if pair
    end
  end

  # A `started` state line's real prerequisite is the PRECEDING stage's artifact, not its own
  # (a `started` line legitimately fires before its own stage's file is real by design). `Exec
  # started` additionally requires plan.md, since Exec cannot start before How produced it too.
  SAVEPOINT_STATE_PREREQUISITES = {
    ["How", "started"] => ["spec.md"],
    ["Exec", "started"] => ["plan.md", "checklist.md"],
  }.freeze

  # Raw (stripped) ledger lines whose disk evidence contradicts them, each paired with a short
  # reason: [line, reason]. Three phantom classes (D5):
  #   - a file-landing milestone whose file is absent or still a sentinel placeholder;
  #   - a duplicate (stage, milestone) pair (the later occurrence is the phantom);
  #   - a state line (`How started` / `Exec started`) whose stage prerequisites are absent.
  # A clean ledger, or an absent one, returns [].
  def self.savepoint_phantom_lines(intent_dir)
    path = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(path)

    landing = savepoint_file_landing_pairs(intent_dir)
    seen = []
    phantoms = []

    File.read(path).each_line do |raw|
      line = raw.strip
      next if line.empty?
      parts = line.split(/\s{2,}/)
      next if parts.length < 3
      pair = [parts[1], parts[2]]

      if seen.include?(pair)
        phantoms << [line, "duplicate (stage, milestone) pair"]
        next
      end
      seen << pair

      if (basename = landing[pair]) && !stage_file_present?(File.join(intent_dir, basename))
        phantoms << [line, "milestone file absent or still a sentinel placeholder"]
        next
      end

      prereqs = SAVEPOINT_STATE_PREREQUISITES[pair]
      if prereqs && prereqs.any? { |b| !stage_file_present?(File.join(intent_dir, b)) }
        phantoms << [line, "state line prerequisite absent on disk"]
      end
    end

    phantoms
  end

  # Pure compute (intent 230): build the bridge state and write NOTHING. `derive`
  # is the writing wrapper over this; `arm` and `repair_lock` use the pure form so
  # the single bridge write happens only after the delivery lock and the worktree
  # have both settled. Joins the pure `derive_stage` / `derive_key` family.
  def self.derive_data(session, intent_id:, intent_dir:, store:, name:)
    stage = derive_stage(intent_dir)
    has = has_files(intent_dir)
    missing = missing_for_stage(stage, intent_dir) - has

    {
      "session" => session,
      "intent" => {
        "id" => intent_id,
        "dir" => intent_dir.sub("#{store}/", ""),
        "store" => store,
        "name" => name
      },
      "build" => {
        "stage" => stage,
        "has" => has,
        "missing" => missing,
        "gate_failures" => 0,
        "auto" => false,
        "last_activity" => Time.now.utc.iso8601
      },
      "observe" => {
        "last_transition" => nil,
        "insights_count" => 0,
        "chain_spawned" => []
      },
      "tokens" => {
        "context_pct" => 0,
        "warning_at" => 80,
        "critical_at" => 90
      },
      # Worktree isolation block (intent 73c; store-worktree half retired by
      # intent 178). Born unprovisioned; arm_auto calls Worktree.provision to
      # fill it. "code" is an abs path or null.
      "worktree" => {
        "code" => nil,
        "code_branch" => nil,
        "provisioned" => false
      },
      # Delivery-lock CACHE block (intent 108, D2). The durable truth is the
      # delivery.lock file in the intent dir; arm fills this cache from it.
      "lock" => {
        "owner_session" => nil,
        "acquired_at" => nil,
        "host" => nil,
        "type" => nil,
        "delegates" => []
      }
    }
  end

  # Compute AND persist. Contract unchanged (intent 230 kept it deliberately):
  # `scripts/hook-session-start` calls this and wants the immediate write, and
  # test/bridge_worktree_derive_test.rb pins write-on-call.
  def self.derive(session, intent_id:, intent_dir:, store:, name:, tmp: tmp_dir)
    data = derive_data(session, intent_id: intent_id, intent_dir: intent_dir,
                       store: store, name: name)
    write(session, data, tmp: tmp)
    data
  end

  # Gate check: returns nil if allowed, or an error message string if blocked
  PROJECT_CONFIG_DEFAULTS = {
    "governing_docs" => ["AGENTS.md"],
    "release" => {
      "on_complete" => "commit",
    },
  }.freeze

  def self.read_project_config(slug)
    path = File.join(Dir.home, ".plastic", "projects", slug, "project.yml")
    config = if File.exist?(path)
               YAML.safe_load(File.read(path)) || {}
             else
               {}
             end

    deep_merge(PROJECT_CONFIG_DEFAULTS, config)
  rescue => e
    $stderr.puts "Warning: failed to read project config for #{slug}: #{e.message}"
    PROJECT_CONFIG_DEFAULTS.dup
  end

  # --- Auto mode (intent 27) ---

  # Intent 230: freshly composed state carries worktree.code = nil, so a failed
  # Worktree.provision would have nothing to keep. Seed the block from the bridge
  # already on disk when it names a code path, so provision's keep-rule (see
  # Worktree.provision) can preserve it. Provision SUCCESS overwrites this with
  # the freshly resolved (identical) pointer, so this only matters on failure.
  def self.carry_prior_worktree(data, session, tmp: tmp_dir)
    prior = read(session, intent_id: data.dig("intent", "id"), tmp: tmp)
    block = prior && prior["worktree"]
    data["worktree"] = block if block.is_a?(Hash) && !blank?(block["code"])
    data
  end
  private_class_method :carry_prior_worktree

  # Shared arming spine (intent 96): resolve the session key, derive intent state,
  # set the caller-controlled auto flag, acquire the delivery lock, provision the
  # per-intent worktrees, persist, and purge terminal bridges. arm_auto (auto: true)
  # and arm_guided (auto: false) are thin delegators so the lock-stamp + provision
  # behaviour stays identical across both modes. Works even when no bridge exists
  # yet (mid-session intent creation).
  def self.arm(session, intent_id:, intent_dir:, store:, name:, auto:, harness: nil,
               agent: nil, model: nil, thread: nil)
    key = resolve_session(session, intent_id: intent_id, store: store)
    if blank?(session) && blank?(ENV["CLAUDE_CODE_SESSION_ID"])
      $stderr.puts "plastic: no session id available; arming with derived bridge key #{key}"
    end
    # Compute only (intent 230). Nothing reaches disk until the lock is ours and
    # the worktree has settled; a LockHeldError below must leave the previous
    # bridge exactly as it was.
    data = derive_data(key, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name)
    data["build"]["auto"] = auto

    # Acquire the durable delivery lock (D1/D2): session-keyed, O_EXCL, in the
    # intent dir. The bridge lock block is a cache of the file.
    intent_dir_abs = File.expand_path(intent_dir)
    status, lock_data = Lock.acquire(intent_dir_abs, session: key,
                                     harness: harness, agent: agent,
                                     model: model, thread: thread,
                                     run_mode: auto ? "auto" : "guided")
    case status
    when :acquired, :owned
      data["lock"] = lock_cache(lock_data)
    when :held
      raise LockHeldError, "delivery lock for intent #{intent_id} is held by " \
        "session #{lock_data && lock_data['owner_session']}; run " \
        "#{skill_ref('plastic-doctor', harness: harness)} check the lock status"
    when :stale
      raise LockHeldError, "delivery lock for intent #{intent_id} is stale " \
        "(owner #{lock_data && lock_data['owner_session']}); run " \
        "#{skill_ref('plastic-doctor', harness: harness)} reclaim the lock to take it " \
        "over with an audit"
    when :excluded
      raise LockHeldError, "a #{lock_data && lock_data['type']} lock is active on " \
        "intent #{intent_id}; run #{skill_ref('plastic-doctor', harness: harness)} check " \
        "the lock status"
    when :corrupt
      raise LockHeldError, "delivery.lock for intent #{intent_id} is unreadable; " \
        "run #{skill_ref('plastic-doctor', harness: harness)} fix the lock"
    end

    carry_prior_worktree(data, key)

    # Provision the per-intent worktrees (mandatory code worktree for project
    # intents; fail-open for non-git / global-only). Never let a provision error
    # break arming: the lock and auto flag still matter.
    begin
      Worktree.provision(data)
    rescue => e
      $stderr.puts "plastic: worktree provision raised, continuing unprovisioned: #{e.message}"
    end

    write(key, data)
    purge_done_bridges(session: key)
    data
  end
  private_class_method :arm

  # Arm auto mode for a session+intent. Works even when no bridge exists yet
  # (mid-session intent creation). Re-derives intent state, then sets build.auto.
  def self.arm_auto(session, intent_id:, intent_dir:, store:, name:, harness: nil,
                    agent: nil, model: nil, thread: nil)
    arm(session, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name,
        auto: true, harness: harness, agent: agent, model: model, thread: thread)
  end

  # Acquire the delivery lock WITHOUT auto mode (intent 96 / Start guided branch).
  # Mirrors arm_auto's lock-stamp + worktree provision but leaves build.auto = false.
  # Same signature as arm_auto; disarm_auto (mode-agnostic) releases a guided lock.
  def self.arm_guided(session, intent_id:, intent_dir:, store:, name:, harness: nil,
                      agent: nil, model: nil, thread: nil)
    arm(session, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name,
        auto: false, harness: harness, agent: agent, model: model, thread: thread)
  end

  # Degrade path for disarm_auto when no intent_id is given (intent 131): the
  # session's sole per-intent bridge when there is exactly one, else the
  # legacy single-key file. Keeps the common single-intent auto path working
  # without every caller having to name the intent id explicitly. With TWO or
  # more per-intent bridges it refuses to guess (intent 233); see below.
  def self.sole_bridge_data(session, tmp: tmp_dir)
    matches = Dir.glob(File.join(tmp, "plastic-#{session}--*.json")).reject { |f| f.end_with?(".tmp") }
    if matches.length == 1
      data = (JSON.parse(File.read(matches.first)) rescue nil)
      return data if data
    end
    # Refuse to guess among siblings (intent 233): with 2+ per-intent bridges
    # the legacy single-key file below can carry EITHER sibling, so falling
    # through would let a no-id disarm release the wrong intent's lock. A
    # disarm that does nothing is recoverable; one that unlocks a live
    # delivery is not. Zero matches keeps the legacy fallback (131 migration).
    if matches.length > 1
      $stderr.puts "plastic: session #{session} has #{matches.length} bridges; " \
                   "disarm needs an explicit intent_id (refusing to guess)"
      return nil
    end
    read(session, tmp: tmp)
  end

  # Disarm. No-op if no bridge exists for the session. End-tail order (D6):
  # worktrees are merged/removed FIRST (the verify step is the caller's,
  # before disarm), then the delivery lock is cleared, and only then does the
  # bridge become purge-eligible. purge_done_bridges enforces the same order
  # defensively by skipping any bridge whose intent still holds a lock.
  #
  # Now takes intent_id (intent 131): a session can own SEVERAL live bridges
  # (one per concurrent intent), so disarm must target ONE of them. When
  # intent_id is nil, degrades to the session's sole bridge (see
  # sole_bridge_data) so the common single-intent path keeps working.
  #
  # The lock clear is conditional (intent 233): a failed release leaves the
  # cached lock fields alone so the orphan stays findable.
  def self.disarm_auto(session, intent_id: nil)
    data = blank?(intent_id) ? sole_bridge_data(session) : read(session, intent_id: intent_id)
    return nil unless data
    data["build"] ||= {}
    data["build"]["auto"] = false

    # Release the worktrees the matching arm provisioned (intent 73c). Non-fatal:
    # a release error must not block disarming. CLEANUP (73c3) refines the
    # merge-vs-remove policy on the completion/release path.
    begin
      Worktree.release(data)
    rescue => e
      $stderr.puts "plastic: worktree release raised, continuing: #{e.message}"
    end

    # Check what the release actually DID before touching the cache (intent
    # 233). Blanking the cache after a failed release orphans the durable
    # delivery.lock: the file stays on disk and nothing points at it any more.
    # Rescue mirrors the Worktree.release rescue above: warn, never raise,
    # never abort the rest of the tail (the guard fails milder than the bug).
    dir = bridge_intent_dir(data)
    release_status = nil
    if dir
      owner = data.dig("lock", "owner_session")
      owner = session if blank?(owner)
      begin
        release_status = Lock.release(dir, session: owner)
      rescue => e
        release_status = :raised
        $stderr.puts "plastic: delivery lock release raised for #{dir}, continuing: #{e.message}"
      end
    end

    # Success means "no lock left on disk": :released (we deleted it), :none
    # (there was none), and nil (no intent dir, so no release was attempted).
    # Only :not_owner and a raised release keep the cache pointing at the lock
    # so plastic-lock fix / reclaim / doctor can still find and repair it.
    if release_status.nil? || release_status == :released || release_status == :none
      data["lock"] = { "owner_session" => nil, "acquired_at" => nil,
                       "host" => nil, "type" => nil, "delegates" => [] }
    else
      $stderr.puts "plastic: delivery lock NOT released for #{dir} (#{release_status}); " \
                   "bridge lock cache preserved for repair"
      data["lock"] = {} unless data["lock"].is_a?(Hash)
    end
    # Diagnostic only (D5): the primary contract stays "owner_session non-nil
    # after disarm means the lock was not released".
    data["lock"]["release_status"] = release_status.nil? ? nil : release_status.to_s

    write(session, data)
    purge_done_bridges(session: session)
    data
  end

  # One deterministic, idempotent repair (intent 108, D5): diagnose, remove
  # faulty own-side state, rebuild the durable lock AND the bridge cache from
  # disk truth for the current session. Legacy /tmp-only pid locks are
  # migrated here: the delivery.lock file is created and the cache rebuilt
  # without a pid. NEVER touches a fresh foreign lock (reports "held"); a
  # stale foreign lock reports "stale" and is taken only by the explicit
  # reclaim verb (Lock.takeover). Two entry points call this: the
  # plastic-lock CLI and /plastic-intent-starting (self-healing boarding).
  def self.repair_lock(session, intent_id:, intent_dir:, store:, name:,
                       now: Time.now, tmp: tmp_dir, harness: nil,
                       agent: nil, model: nil, thread: nil, run_mode: nil,
                       hint_harness: nil)
    key = resolve_session(session, intent_id: intent_id, store: store)
    dir = File.expand_path(intent_dir)
    actions = []
    previous = read(key, intent_id: intent_id, tmp: tmp)
    auto = !!(previous && previous.dig("build", "auto"))
    derived_mode = if previous && previous.dig("build").is_a?(Hash) &&
                      previous["build"].key?("auto")
                     auto ? "auto" : "guided"
                   end
    identity = { harness: harness, agent: agent, model: model, thread: thread,
                 run_mode: blank?(run_mode) ? derived_mode : run_mode.to_s }

    if Lock.corrupt?(dir)
      File.delete(Lock.path(dir))
      actions << "removed corrupt delivery.lock"
    end

    lock = Lock.read(dir)
    if lock && !Lock.authorized?(lock, key)
      if Lock.fresh?(dir, now: now)
        return { "status" => "held", "owner" => lock["owner_session"],
                 "actions" => actions, "session" => key }
      end
      return { "status" => "stale", "owner" => lock["owner_session"],
               "actions" => actions, "session" => key,
               "hint" => "run #{skill_ref('plastic-doctor', harness: hint_harness || harness)} reclaim the " \
                         "lock to take over with an audit" }
    end

    if lock
      if lock["owner_session"].to_s == key.to_s
        lock_data = lock.dup
        { "owner_harness" => harness, "owner_agent" => agent,
          "owner_model" => model, "owner_thread" => thread,
          "run_mode" => identity[:run_mode] }.each do |field, value|
          lock_data[field] = value.to_s unless blank?(value)
        end
        Lock.write(dir, lock_data)
        Lock.heartbeat(dir, session: key, now: now)
      else
        Lock.heartbeat(dir, session: key, now: now)
        lock_data = Lock.read(dir)
      end
      role = lock_data["owner_session"].to_s == key ? "owner" : "delegate"
      actions << "lock kept (#{role})"
    else
      status, lock_data = Lock.acquire(dir, session: key, now: now, **identity)
      actions << "lock #{status}"
    end

    data = derive_data(key, intent_id: intent_id, intent_dir: dir, store: store,
                       name: name)
    data["build"]["auto"] = auto
    data["lock"] = lock_cache(lock_data)

    carry_prior_worktree(data, key, tmp: tmp)

    # Provision the per-intent worktrees so the rebuilt bridge carries
    # worktree.code (intent 136). Without it, cwd/edited-path selection has no
    # key: the repaired intent loses its own code gate and a concurrent sibling
    # wins the tie-break. Idempotent (reuse dir / reattach branch) and fail-open
    # for non-git / global-only, exactly as `arm` does; never break the repair.
    begin
      Worktree.provision(data)
    rescue => e
      $stderr.puts "plastic: worktree provision raised during repair, continuing unprovisioned: #{e.message}"
    end

    write(key, data, tmp: tmp)
    actions << "bridge rebuilt from disk (stage #{data['build']['stage']})"

    { "status" => "repaired", "actions" => actions,
      "lock" => lock_data, "session" => key }
  end

  # "<id>" from a ".../store/<id>--<slug>" dir, else nil.
  def self.intent_id_from_dir(dir)
    base = File.basename(dir.to_s)
    base.include?("--") ? base.split("--", 2).first : nil
  end

  def self.deep_merge(base, overlay)
    result = base.dup
    overlay.each do |key, value|
      if value.is_a?(Hash) && result[key].is_a?(Hash)
        result[key] = deep_merge(result[key], value)
      else
        result[key] = value
      end
    end
    result
  end
end
