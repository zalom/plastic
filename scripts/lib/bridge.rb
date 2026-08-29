#!/usr/bin/env ruby
# encoding: UTF-8

require "json"
require "yaml"
require "fileutils"
require "digest"
require_relative "worktree"
require_relative "lock"
require_relative "savepoint"

module Bridge
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

  # Pure compute (intent 230): build the bridge state and write NOTHING. `derive`
  # is the writing wrapper over this; `arm` and `repair_lock` use the pure form so
  # the single bridge write happens only after the delivery lock and the worktree
  # have both settled. Joins the pure `derive_stage` / `derive_key` family.
  def self.derive_data(session, intent_id:, intent_dir:, store:, name:)
    stage = Savepoint.derive_stage(intent_dir)
    has = Savepoint.has_files(intent_dir)
    missing = Savepoint.missing_for_stage(stage, intent_dir) - has

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
