#!/usr/bin/env ruby
# encoding: UTF-8

require "json"
require "yaml"
require "fileutils"
require "tempfile"
require "digest"

module Bridge
  STAGES = %w[what why how exec done].freeze

  # Placeholder sentinel (intent 60b). A scaffolded lifecycle file
  # (spec.md/plan.md/checklist.md/outcome.md) carries this exact string as its
  # first line until an agent fills the file and deletes the sentinel. The
  # sentinel is the "stage not reached yet" marker, so stage detection treats a
  # sentinel-marked file as absent (see stage_file_present?). The intent file
  # (<id>--<slug>.md) is never sentineled; it is born complete.
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"

  # Stale-bridge purge window (intent 67). The bridge file is ephemeral
  # live-session gate state, NOT a continuation source: an intent is resumed from
  # its savepoint.md ledger, never from a /tmp bridge. So any bridge older than
  # this window is dead weight and safe to purge, regardless of arm state. No
  # real session stays live for two days, so a 48h cutoff never removes a bridge
  # an active run depends on.
  PURGE_AGE_SECONDS = 48 * 3600   # 48 hours

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

  def self.path(session, tmp: tmp_dir)
    "#{tmp}/plastic-#{session}.json"
  end

  # --- Session resolution (intent 52) ----------------------------------------

  def self.blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # Deterministic, session-id-less bridge key derived from store + intent id.
  # Stable across processes so a session-less arm and a later session-less
  # gate-check resolve to the same bridge file.
  def self.derive_key(store, intent_id)
    "auto-" + Digest::SHA256.hexdigest("#{store}/#{intent_id}")[0, 10]
  end

  # Resolve a bridge session: first non-empty of explicit, CLAUDE_SESSION_ID,
  # CLAUDE_CODE_SESSION_ID, then a derived key. Never returns nil/empty.
  # Whitespace-only counts as empty.
  #
  # The CLAUDE_CODE_SESSION_ID fallback (intent 79) is additive: it only changes
  # behavior when CLAUDE_SESSION_ID is blank but CLAUDE_CODE_SESSION_ID is set —
  # the bg/headless case where the real session id lives in CLAUDE_CODE_SESSION_ID.
  # Keying by the real id (instead of a derived hash) lets the statusline, which
  # receives that same id on stdin, find the bridge by direct filename lookup.
  def self.resolve_session(explicit, intent_id:, store:)
    return explicit.to_s.strip unless blank?(explicit)
    env = ENV["CLAUDE_SESSION_ID"]
    return env.to_s.strip unless blank?(env)
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

  # Resolve the active bridge. Exact-session lookup first; otherwise scan tmp:
  # for plastic-*.json, keep only valid bridges, prefer auto-armed, then prefer
  # the one whose intent.store matches cwd, tie-break by newest mtime.
  def self.discover_bridge(session:, cwd: Dir.pwd, tmp: tmp_dir)
    if !blank?(session) && File.exist?(path(session, tmp: tmp))
      exact = read(session, tmp: tmp)
      return exact if bridge_valid?(exact)
    end

    candidates = Dir.glob(File.join(tmp, "plastic-*.json")).reject { |f| f.end_with?(".tmp") }
    parsed = candidates.filter_map do |f|
      data = (JSON.parse(File.read(f)) rescue nil)
      next unless data && bridge_valid?(data)
      { file: f, data: data, mtime: File.mtime(f) }
    end
    return nil if parsed.empty?

    auto = parsed.select { |c| c[:data].dig("build", "auto") == true }
    pool = auto.empty? ? parsed : auto

    unless blank?(cwd)
      cwd_abs = File.expand_path(cwd)
      matching = pool.select do |c|
        store = c[:data].dig("intent", "store").to_s
        next false if store.empty?
        store_abs = File.expand_path(store)
        cwd_abs == store_abs ||
          cwd_abs.start_with?("#{store_abs}/") ||
          store_abs.start_with?("#{cwd_abs}/")
      end
      pool = matching unless matching.empty?
    end

    pool.max_by { |c| c[:mtime] }&.fetch(:data)
  end

  # --- Stale-bridge purge (intent 67) ---------------------------------------
  #
  # Remove stale tmp/plastic-*.json bridge files so discover_bridge's per-fire
  # scan stays bounded. Best-effort and non-raising: returns the array of removed
  # paths. Continuation does not depend on these files (an intent resumes from its
  # savepoint.md ledger), so the only safety rule is age: a bridge older than
  # max_age_seconds is purged regardless of arm state, while anything newer is kept
  # (it may be a live run). The current session's own bridge is never purged
  # (preserves the disarm_auto contract that it stays readable). Wired into
  # arm_auto and disarm_auto so both manual and auto delivery keep the temp dir
  # clean.
  def self.purge_stale_bridges(session:, now: Time.now, max_age_seconds: PURGE_AGE_SECONDS,
                               tmp: tmp_dir)
    current = path(session, tmp: tmp)
    removed = []
    Dir.glob(File.join(tmp, "plastic-*.json")).each do |f|
      next if f == current
      begin
        next if (now - File.mtime(f)) < max_age_seconds
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
    $stderr.puts "plastic: purge_stale_bridges failed: #{e.message}"
    removed || []
  end

  def self.read(session, tmp: tmp_dir)
    p = path(session, tmp: tmp)
    return nil unless File.exist?(p)
    JSON.parse(File.read(p))
  rescue JSON::ParserError
    nil
  end

  def self.write(session, data, tmp: tmp_dir)
    raise ArgumentError, "bridge session must be present" if blank?(session)
    p = path(session, tmp: tmp)
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

  def self.derive_stage(intent_dir)
    return "done" if stage_file_present?("#{intent_dir}/outcome.md")
    if stage_file_present?("#{intent_dir}/plan.md") &&
       File.directory?("#{intent_dir}/actions") &&
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
    files << "actions/" if File.directory?("#{intent_dir}/actions")
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

  # Append a milestone line for file_path if (and only if) it is a milestone
  # not already recorded. Returns true when a line was written, false otherwise.
  def self.append_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_milestone(intent_dir, basename)
    return false unless milestone
    # A sentinel-marked lifecycle file logs NO milestone (the stage is not real
    # yet). The intent file is never sentineled, so it still logs its What line.
    return false unless stage_file_present?(File.join(intent_dir, basename))
    return false if savepoint_recorded_milestones(intent_dir).include?(milestone)

    line = "#{now.utc.iso8601}  #{stage}  #{milestone}\n"
    File.open(File.join(intent_dir, SAVEPOINT_FILE), "a") { |io| io.write(line) }
    true
  end

  # Reconstruct the ledger from files on disk (timestamps from mtimes), in
  # stage order, overwriting savepoint.md. Returns the number of lines written.
  def self.rebuild_savepoint(intent_dir)
    ordered = [
      File.basename(intent_file(intent_dir)),
      "spec.md", "plan.md", "checklist.md", "outcome.md",
    ]
    lines = ordered.filter_map do |basename|
      path = File.join(intent_dir, basename)
      next unless stage_file_present?(path)
      stage, milestone = savepoint_milestone(intent_dir, basename)
      next unless milestone
      "#{File.mtime(path).utc.iso8601}  #{stage}  #{milestone}\n"
    end
    File.write(File.join(intent_dir, SAVEPOINT_FILE), lines.join)
    lines.length
  end

  def self.derive(session, intent_id:, intent_dir:, store:, name:)
    stage = derive_stage(intent_dir)
    has = has_files(intent_dir)
    missing = missing_for_stage(stage, intent_dir) - has

    data = {
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
      }
    }

    write(session, data)
    data
  end

  # Gate check: returns nil if allowed, or an error message string if blocked
  def self.check_gate(intent_dir, file_being_written)
    basename = File.basename(file_being_written)

    case basename
    when "spec.md"
      ifile = intent_file(intent_dir)
      unless File.exist?(ifile) && File.read(ifile).include?("## Intent")
        return "Cannot start Why — What is incomplete (#{File.basename(ifile)} missing or no ## Intent)"
      end
    when "plan.md"
      unless stage_file_present?("#{intent_dir}/spec.md")
        return "Cannot start How — Why is incomplete (spec.md missing)"
      end
    when "checklist.md"
      unless stage_file_present?("#{intent_dir}/plan.md") && File.directory?("#{intent_dir}/actions")
        return "Cannot complete How — plan.md or actions/ missing"
      end
    when "outcome.md"
      checklist = "#{intent_dir}/checklist.md"
      if stage_file_present?(checklist)
        content = File.read(checklist)
        unchecked = content.scan(/^- \[ \]/).length
        if unchecked > 0
          return "Cannot complete Exec — #{unchecked} unchecked items in checklist.md"
        end
      end
    end

    nil # no gate violation
  end

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

  # Arm auto mode for a session+intent. Works even when no bridge exists yet
  # (mid-session intent creation). Re-derives intent state, then sets build.auto.
  def self.arm_auto(session, intent_id:, intent_dir:, store:, name:)
    key = resolve_session(session, intent_id: intent_id, store: store)
    if blank?(session) && blank?(ENV["CLAUDE_SESSION_ID"]) && blank?(ENV["CLAUDE_CODE_SESSION_ID"])
      $stderr.puts "plastic: no session id available; arming auto with derived bridge key #{key}"
    end
    data = derive(key, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name)
    data["build"]["auto"] = true
    write(key, data)
    purge_stale_bridges(session: key)
    data
  end

  # Disarm auto mode. No-op if no bridge exists for the session.
  def self.disarm_auto(session)
    data = read(session)
    return nil unless data
    data["build"] ||= {}
    data["build"]["auto"] = false
    write(session, data)
    purge_stale_bridges(session: session)
    data
  end

  # Decide whether a code edit should be blocked while auto mode is armed.
  # Returns a reason string to BLOCK, or nil to ALLOW.
  #
  # Blocks iff: auto armed AND intent hasn't reached How (stage what/why) AND the
  # target is project code — i.e. NOT under ~/.plastic and NOT inside the intent dir.
  def self.code_gate_decision(bridge_data, file_path, home: Dir.home)
    return nil unless bridge_data.is_a?(Hash)
    build = bridge_data["build"] || {}
    return nil unless build["auto"] == true

    intent_info = bridge_data["intent"] || {}
    store = intent_info["store"]
    dir = intent_info["dir"]
    return nil unless store && dir
    intent_dir_abs = File.expand_path("#{store}/#{dir}")

    # "How reached" = the plan triplet exists. Gate by artifact presence, not the
    # stage label (derive_stage returns "how" as soon as spec.md exists, before any
    # plan). Code edits stay blocked until plan.md + checklist.md are both present.
    reached_how = stage_file_present?("#{intent_dir_abs}/plan.md") &&
                  stage_file_present?("#{intent_dir_abs}/checklist.md")
    return nil if reached_how

    file_abs = File.expand_path(file_path.to_s)
    plastic_home = File.expand_path(File.join(home, ".plastic"))
    return nil if file_abs == plastic_home || file_abs.start_with?("#{plastic_home}/")
    return nil if file_abs == intent_dir_abs || file_abs.start_with?("#{intent_dir_abs}/")

    id = intent_info["id"]
    "intent #{id} has not reached How — write plan.md + checklist.md before " \
      "editing project code. Run plastic-auto or plastic-writing-plans first. " \
      "(blocked edit: #{file_abs})"
  end

  # --- Bash-edit gate (intent 27a) ---

  # Extract the set of file paths a Bash command writes to. Conservative by
  # design: it is acceptable to miss exotic forms, but it must NOT flag reads
  # or /dev/null. Returns an Array of path strings (possibly relative).
  #
  # Covered write vectors: redirection (>, >>, including heredoc `cat > f <<EOF`),
  # tee / tee -a, sed -i / sed -i.bak, cp/mv (last non-flag arg), dd of=.
  def self.bash_write_targets(command)
    return [] unless command.is_a?(String)

    targets = []
    targets.concat(bash_redirect_targets(command))
    # Split on command separators for per-segment utility parsing.
    command.split(/[;\n]|&&|\|\||\|/).each do |segment|
      targets.concat(bash_utility_targets(segment))
    end
    targets.uniq
  end

  # Redirections: `> path` / `>> path`, but not fd dups (`2>&1`) or /dev/null.
  # A leading digit (fd number) before > is fine; `>&` is a dup and excluded.
  def self.bash_redirect_targets(command)
    targets = []
    # Match optional leading fd digits, then > or >>, not followed by & , then path.
    command.scan(/\d*>>?(?!&)\s*([^\s;|&<>]+)/) do |m|
      path = m[0]
      next if path.nil? || path.empty?
      next if dev_null?(path)
      targets << path
    end
    targets
  end

  def self.bash_utility_targets(segment)
    tokens = segment.strip.split(/\s+/)
    return [] if tokens.empty?

    # Find the utility name, skipping env-style assignments.
    idx = 0
    idx += 1 while tokens[idx] && tokens[idx].include?("=") && tokens[idx] !~ /^-/ && !tokens[idx].start_with?("of=")
    util = File.basename(tokens[idx].to_s)
    args = tokens[(idx + 1)..] || []

    case util
    when "tee"
      tee_targets(args)
    when "sed"
      sed_targets(args)
    when "cp", "mv"
      copy_move_targets(args)
    when "dd"
      dd_targets(tokens)
    else
      []
    end
  end

  def self.tee_targets(args)
    args.reject { |a| a.start_with?("-") || dev_null?(a) }
  end

  def self.sed_targets(args)
    # In-place only: -i or -i.bak (suffix attached). Otherwise sed reads.
    inplace = args.any? { |a| a == "-i" || a.start_with?("-i") }
    return [] unless inplace
    files = args.reject { |a| a.start_with?("-") }
    # sed args: script then file(s). First non-flag is the script expression
    # unless an -e/-f was used; conservatively treat the LAST non-flag as file.
    files.empty? ? [] : [files.last].reject { |f| dev_null?(f) }
  end

  def self.copy_move_targets(args)
    files = args.reject { |a| a.start_with?("-") }
    return [] if files.length < 2
    dest = files.last
    dev_null?(dest) ? [] : [dest]
  end

  def self.dd_targets(tokens)
    tokens.each_with_object([]) do |t, acc|
      next unless t.start_with?("of=")
      path = t.sub("of=", "")
      acc << path unless path.empty? || dev_null?(path)
    end
  end

  def self.dev_null?(path)
    path == "/dev/null" || path.start_with?("/dev/")
  end

  # Decide whether a Bash command should be blocked under the auto-mode code
  # gate. Resolves each write target against cwd and applies the SAME policy as
  # code_gate_decision. Returns the first block reason, or nil to allow.
  def self.bash_gate_decision(bridge_data, command, cwd:, home: Dir.home)
    bash_write_targets(command).each do |target|
      abs = File.absolute_path?(target) ? target : File.join(cwd, target)
      reason = code_gate_decision(bridge_data, abs, home: home)
      return reason if reason
    end
    nil
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
