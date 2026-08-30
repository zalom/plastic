# encoding: UTF-8
# frozen_string_literal: true

# Core half of the Plastic doctor (intent 228). Holds run_core_checks and every
# method, constant and require it reaches, and nothing else, so the SessionStart
# hook can load the boot check without pulling in the full 3,100-line diagnostic
# engine. scripts/doctor.rb requires this file and reopens the same class to add
# the store, conventions, intent and CLI halves, so Doctor stays one class with
# one public surface and one definition of which checks are core (intent 36a).

require "json"
require "yaml"
require "time"
require "digest"
require "rubygems"

require_relative "hook_registry"
require_relative "compact_instructions"

class Doctor
  DEFAULT_PLASTIC_HOME = File.join(Dir.home, ".plastic")

  DEFAULT_AGENTS = {
    "claude" => { name: "Claude Code", dir: File.join(Dir.home, ".claude") },
    "codex"  => { name: "Codex CLI",   dir: File.join(Dir.home, ".agents"),
                  home_dir: File.join(Dir.home, ".codex") },
    "hermes" => { name: "Hermes",      dir: File.join(Dir.home, ".hermes") },
  }.freeze

  # The Claude events hooks_registered expects in settings.json: the five-event map of
  # cut-inventory 3b (intent 309 added SessionEnd, registered for close since intent 301).
  CLAUDE_HOOK_EVENTS = %w[SessionStart PreCompact PostToolUse UserPromptSubmit SessionEnd].freeze

  # Launchers the installer places in the agent's hooks dir that are NOT hooks
  # (intent 204): plastic-statusline is the settings["statusLine"] command, wired
  # outside HookRegistry.events entirely, so it must be excluded from the
  # orphan-launcher scan below or a correct install would report a false orphan.
  # Defined in HookRegistry (intent 275) so the installer's purge can read it too;
  # this is an alias, not a second source of truth.
  CLAUDE_NON_HOOK_LAUNCHERS = HookRegistry::CLAUDE_NON_HOOK_LAUNCHERS

  REQUIRED_SCRIPTS = %w[
    folgezettel-id
    read-config
    hook-session-start
    hook-capture
    hook-record
    validate-intent
    doctor.rb
  ].freeze

  # The apply_patch PreToolUse veto only fires from Codex v0.123.0 onward
  # (PR #18391, "emit hooks for apply_patch edits"). Below it the veto
  # silently no-ops (intent 184).
  CODEX_HOOKS_FLOOR = "0.123.0"

  attr_reader :plastic_home, :agents

  # Testable shell-out default, mirroring QmdSync.default_runner: a real
  # Open3.capture3 call in production, swappable for a fake in tests so no
  # test needs a real codex binary or a PATH mutation.
  def self.default_runner
    lambda do |args|
      require "open3"
      out, _err, status = Open3.capture3("codex", *args)
      [out, status.success?]
    rescue Errno::ENOENT
      ["", false] # codex not on PATH: undetectable, fail open
    end
  end

  def initialize(plastic_home: DEFAULT_PLASTIC_HOME, agents: DEFAULT_AGENTS,
                  runner: Doctor.default_runner)
    @plastic_home = plastic_home
    @agents = agents
    @runner = runner
  end

  # --- Utility helpers ---

  def read_version
    version_path = File.join(plastic_home, "VERSION")
    return nil unless File.exist?(version_path)

    File.read(version_path).strip
  end

  def read_json_safe(path)
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    content = File.read(path).gsub(%r{//[^\n]*}, "").gsub(/,(\s*[}\]])/, '\1')
    JSON.parse(content)
  rescue
    nil
  end

  def load_yaml_safe(path)
    return nil unless File.exist?(path)

    YAML.safe_load(File.read(path)) || {}
  rescue => e
    $stderr.puts "Warning: failed to parse #{path}: #{e.message}"
    nil
  end

  def tilde(path)
    path.sub(Dir.home, "~")
  end

  # Every hook command string registered under one settings.json event, flattened
  # across that event's matcher groups. Shape-tolerant on purpose: settings.json is
  # hand-editable and may carry anything at all under an event key.
  def event_commands(groups)
    return [] unless groups.is_a?(Array)

    groups.flat_map do |group|
      next [] unless group.is_a?(Hash) && group["hooks"].is_a?(Array)

      group["hooks"].map { |h| h.is_a?(Hash) ? h["command"].to_s : "" }
    end
  end

  # Every (event, command) pair, unfiltered (intent 276).
  def each_hook_command(hooks_hash)
    return unless hooks_hash.is_a?(Hash)

    hooks_hash.each do |event, groups|
      group_list = groups.is_a?(Hash) ? [groups] : Array(groups)
      group_list.each do |g|
        next unless g.is_a?(Hash)

        # A bare Hash is one entry, not a skipped group (review finding).
        hooks_list = case g["hooks"]
                     when Array then g["hooks"]
                     when Hash then [g["hooks"]]
                     end
        next unless hooks_list

        hooks_list.each do |h|
          cmd = h.is_a?(Hash) ? h["command"].to_s : ""
          yield event, cmd unless cmd.empty?
        end
      end
    end
  end

  # Candidate start positions before end_pos: string start, or right after
  # whitespace or an opening quote (round 3).
  def command_boundaries(raw, end_pos)
    boundaries = [0]
    (0...end_pos).each do |i|
      ch = raw[i]
      boundaries << i + 1 if ch =~ /\s/ || ch == '"' || ch == "'"
    end
    boundaries.uniq.sort
  end

  # Strip a quote pair only when it wraps the WHOLE string; never delete a
  # quote character inside it (that broke a real apostrophe, round 3).
  def strip_balanced_quotes(str)
    if str.length >= 2 && (str[0] == '"' || str[0] == "'") && str[0] == str[-1]
      str[1..-2]
    else
      str
    end
  end

  # End position of the leftmost known launcher name in raw, matched whole
  # (optionally + ".rb"); nil if none appears.
  def launcher_name_end_position(raw, known_names)
    positions = known_names.filter_map do |name|
      m = raw.match(/(?<![\w.-])#{Regexp.escape(name)}(\.rb)?(?=["'\s]|\z)/)
      m && [m.begin(0), m.end(0)]
    end
    return nil if positions.empty?

    positions.min_by(&:first).last
  end

  # Mode (b): true unless a launcher this command names is missing (round 3
  # candidate design: see command_boundaries/strip_balanced_quotes above).
  def launcher_on_disk?(cmd, known_names)
    raw = cmd.to_s
    end_pos = launcher_name_end_position(raw, known_names)
    return true unless end_pos

    any_absolute = false
    command_boundaries(raw, end_pos).each do |start|
      candidate = strip_balanced_quotes(raw[start...end_pos])
      next if candidate.empty?

      candidate = File.expand_path(candidate) if candidate.start_with?("~")
      next unless candidate.start_with?("/")

      any_absolute = true
      return true if File.file?(candidate)
    end

    !any_absolute
  end

  # Mode (a): does the EXECUTABLE's basename carry plastic-, never an
  # argument's? Executable = longest leading candidate (whole command, or
  # with a leading word stripped) that resolves to a real file, else the
  # first token, quote-aware (round 3).
  def unowned_prefixed_command?(cmd)
    raw = cmd.to_s
    return false if raw.strip.empty?

    executable = executable_candidate(raw)
    return false unless executable

    File.basename(executable).sub(/\.rb\z/, "").start_with?("plastic-")
  end

  def executable_candidate(raw)
    return resolved_candidate(raw) || after_leading_word(raw) || quote_aware_first_token(raw)
  end

  def after_leading_word(raw)
    first_space = raw.index(/\s/)
    return nil unless first_space

    resolved_candidate(raw[(first_space + 1)..-1].to_s.strip)
  end

  # Quote-stripped, tilde-expanded str, returned only if it resolves to a
  # real file; nil otherwise so the caller tries its next candidate.
  def resolved_candidate(str)
    candidate = strip_balanced_quotes(str)
    return nil if candidate.empty?

    candidate = File.expand_path(candidate) if candidate.start_with?("~")
    candidate if File.file?(candidate)
  end

  def quote_aware_first_token(raw)
    if raw.start_with?('"') || raw.start_with?("'")
      q = raw[0]
      close = raw.index(q, 1)
      return close ? raw[1...close] : raw[1..-1].to_s
    end

    raw.split(/\s+/).reject(&:empty?).first.to_s
  end

  # Shared mode-(a) fix_hint text (intent 276), parametrized by the config
  # file the rename gets re-registered in.
  def unowned_hook_rename_hint(config_file)
    "The plastic- prefix is reserved for Plastic's hooks and skills. Rename your hook and " \
      "re-register it in #{config_file}."
  end

  def check(category:, name:, status:, message:, details: [], fixable: false, fix_hint: nil)
    result = {
      category: category,
      name: name,
      status: status,
      message: message,
      details: details,
      fixable: fixable,
    }
    result[:fix_hint] = fix_hint if fix_hint
    result
  end

  def check_global_store_available
    checks = []

    if File.directory?(plastic_home)
      checks << check(
        category: "global_store", name: "global_store_reachable", status: "pass",
        message: "Global store directory reachable at #{tilde(plastic_home)}"
      )
    else
      checks << check(
        category: "global_store", name: "global_store_reachable", status: "fail",
        message: "Global store directory not found at #{tilde(plastic_home)}",
        fixable: true, fix_hint: "Run the Plastic installer to bootstrap the store"
      )
      return checks
    end

    index_path = File.join(plastic_home, "INDEX.md")
    if File.exist?(index_path)
      checks << check(
        category: "global_store", name: "global_index_reachable", status: "pass",
        message: "INDEX.md exists"
      )
    else
      checks << check(
        category: "global_store", name: "global_index_reachable", status: "fail",
        message: "INDEX.md not found at #{tilde(index_path)}",
        fixable: true, fix_hint: "Run the Plastic installer to bootstrap the store"
      )
    end

    checks
  end

  def check_agent_registration(agent_key)
    checks = []
    config = agents[agent_key]
    agent_dir = config[:dir]

    unless File.directory?(agent_dir)
      checks << check(
        category: "agent_registration", name: "agent_dir_exists", status: "fail",
        message: "Agent directory #{tilde(agent_dir)} not found — #{config[:name]} may not be installed",
        fixable: false
      )
      return checks
    end

    case agent_key
    when "claude"
      checks += check_claude_registration(agent_dir)
    when "codex"
      checks += check_codex_registration(agent_key, agent_dir)
    else
      checks += check_generic_agent_registration(agent_key, agent_dir)
    end

    checks
  end

  def check_claude_registration(agent_dir)
    checks = []
    hooks_dir = File.join(agent_dir, "hooks")

    # Derived from HookRegistry.events (intent 204), not a hand-kept list, so
    # every registered hook is checked.
    expected_launchers = HookRegistry.claude_launcher_names

    # hooks_exist
    missing_hooks = expected_launchers.reject { |h| File.exist?(File.join(hooks_dir, h)) }

    if missing_hooks.empty?
      checks << check(
        category: "agent_registration", name: "hooks_exist", status: "pass",
        message: "All #{expected_launchers.size} expected hook scripts exist"
      )
    else
      checks << check(
        category: "agent_registration", name: "hooks_exist", status: "fail",
        message: "#{missing_hooks.size} hook script(s) missing",
        details: missing_hooks.map { |h| "#{tilde(hooks_dir)}/#{h}" },
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude"
      )
    end

    # hooks_executable
    existing_hooks = expected_launchers
      .map { |h| File.join(hooks_dir, h) }
      .select { |p| File.exist?(p) }

    non_executable = existing_hooks.reject { |p| File.executable?(p) }

    if non_executable.empty?
      checks << check(
        category: "agent_registration", name: "hooks_executable", status: "pass",
        message: "All existing hook scripts are executable"
      )
    else
      checks << check(
        category: "agent_registration", name: "hooks_executable", status: "fail",
        message: "#{non_executable.size} hook script(s) not executable",
        details: non_executable.map { |p| tilde(p) },
        fixable: true, fix_hint: "chmod +x on the listed files"
      )
    end

    # hooks_no_orphans: the mirror of hooks_exist. A plastic-* launcher on disk
    # that HookRegistry does not know about is dead code the next reader would
    # trust as live (the same drift class as a missing launcher, just facing
    # the other way). plastic-statusline is a legitimate non-hook installer
    # artifact (see CLAUDE_NON_HOOK_LAUNCHERS) and is excluded here.
    present_launchers = Dir.glob(File.join(hooks_dir, "plastic-*")).map { |p| File.basename(p) }
    orphans = (present_launchers - expected_launchers - CLAUDE_NON_HOOK_LAUNCHERS).sort

    if orphans.empty?
      checks << check(
        category: "agent_registration", name: "hooks_no_orphans", status: "pass",
        message: "No orphaned hook launchers in #{tilde(hooks_dir)}"
      )
    else
      checks << check(
        category: "agent_registration", name: "hooks_no_orphans", status: "warn",
        message: "#{orphans.size} hook launcher(s) on disk are not registered in HookRegistry",
        details: orphans.map { |h| "#{tilde(hooks_dir)}/#{h}" },
        fixable: true,
        fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude (prunes " \
                  "stale launchers). The plastic- prefix is reserved for Plastic's own hooks: " \
                  "if one of these is yours, rename it (for example to ~/.claude/hooks/" \
                  "writing-style) and re-register it in settings.json before re-running."
      )
    end

    # hooks_registered — settings.json has Plastic hooks for required events
    settings_path = File.join(agent_dir, "settings.json")
    settings = read_json_safe(settings_path)

    if settings.nil?
      checks << check(
        category: "agent_registration", name: "hooks_registered", status: "fail",
        message: "Cannot read #{tilde(settings_path)} — file missing or invalid",
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude"
      )
    else
      hooks = settings["hooks"] || {}

      # A live registration is a launcher Plastic ships TODAY (intent 277).
      # claude_purge_command?, which this replaced, answers "was this ever ours":
      # right for the installer's purge, wrong here, because a SessionStart
      # carrying only the retired plastic-lock-gate satisfied the event while
      # nothing shipped to run it.
      missing_events = CLAUDE_HOOK_EVENTS.reject do |event|
        event_commands(hooks[event]).any? { |cmd| HookRegistry.claude_current_command?(cmd) }
      end

      # Name the launcher when a missing event still carries a Plastic-owned
      # command. Inside a missing event every such command is by construction not
      # a current one, and a bare "SessionStart" reads as "nothing registered" to
      # someone looking at a settings.json that plainly holds a plastic- entry.
      # Events with no Plastic entry keep the bare name: two tests compare details
      # by element equality and by count.
      missing_details = missing_events.map do |event|
        stale = event_commands(hooks[event])
                .flat_map { |cmd| HookRegistry.command_basenames(cmd) }
                .select { |name| HookRegistry.claude_purgeable_launcher_names.include?(name) }
                .uniq
        next event if stale.empty?

        "#{event} (registered command is not a current Plastic hook: #{stale.join(', ')})"
      end

      if missing_events.empty?
        checks << check(
          category: "agent_registration", name: "hooks_registered", status: "pass",
          message: "All #{CLAUDE_HOOK_EVENTS.size} hook events registered in settings.json"
        )
      else
        checks << check(
          category: "agent_registration", name: "hooks_registered", status: "fail",
          message: "#{missing_events.size} hook event(s) not registered in settings.json",
          details: missing_details,
          fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude"
        )
      end

      # hooks_match_registry (intent 108, D7): the live settings must carry
      # EXACTLY the registrations HookRegistry defines; any drift (a missing
      # hook, a stray plastic hook, a stale matcher) is how a hook shipped
      # dead once already.
      expected = HookRegistry.claude_settings_hooks(hook_dir: hooks_dir)
      diffs = []
      # settings.json is hand-editable: "hooks" or a per-event value can be
      # any JSON shape, not only what HookRegistry emits. Guard both here
      # rather than trust .dig / .select on an assumed Hash/Array.
      hooks_value = settings["hooks"].is_a?(Hash) ? settings["hooks"] : {}
      expected.each do |event, group|
        groups = group.is_a?(Array) ? group : [group]
        live = hooks_value[event]
        live = [] unless live.is_a?(Array)
        groups.each do |g|
          matches = live.select { |h| h.is_a?(Hash) && h["matcher"] == g["matcher"] }
          wanted = g["hooks"].map { |h| h["command"] }
          got = matches.flat_map { |m| Array(m["hooks"]).select { |h| h.is_a?(Hash) }.map { |h| h["command"] } }
          missing = wanted - got
          diffs << "#{event}[#{g['matcher']}] missing: #{missing.join(', ')}" unless missing.empty?
        end
      end
      live_plastic = hooks_value.flat_map do |event, groups|
        Array(groups).flat_map do |g|
          next [] unless g.is_a?(Hash) && g["hooks"].is_a?(Array)
          g["hooks"].select { |h| h.is_a?(Hash) }.map { |h| h["command"].to_s }
                    .select { |c| HookRegistry.claude_purge_command?(c) }
                    .map { |c| "#{event}: #{c}" }
        end
      end
      expected_cmds = expected.values.flat_map { |g| g.is_a?(Array) ? g : [g] }
                              .flat_map { |g| g["hooks"].map { |h| h["command"] } }
      strays = live_plastic.reject { |lp| expected_cmds.any? { |c| lp.end_with?(c) } }
      diffs.concat(strays.map { |s| "stray: #{s}" })

      checks << if diffs.empty?
        check(category: "agent_registration", name: "hooks_match_registry",
              status: "pass", message: "settings.json hooks match HookRegistry")
      else
        check(category: "agent_registration", name: "hooks_match_registry",
              status: "fail", message: "#{diffs.size} hook registration(s) diverge from HookRegistry",
              details: diffs, fixable: true,
              fix_hint: "Re-run the installer merge: npx @zalom/plastic update (or ruby ~/.plastic/scripts/install.rb)")
      end

      # hooks_entries_owned: unfiltered unowned/missing-launcher scan (intent 276).
      checks << hooks_entries_owned_check(settings)
    end

    # skills_exist — flat, hyphen-namespaced personal skills (plastic-<name>/)
    checks << flat_skills_check(agent_dir, "--claude")

    # stray_skills — installed plastic-* skill dir with no manifest entry (a leftover,
    # e.g. an old-name copy after a rename; intent 158a AC15)
    checks << stray_skills_check(agent_dir, "--claude", File.join(agent_dir, "plastic", "manifest.json"))

    # agents_exist — auto-mode role files (plastic-*.md) synced into <dir>/agents
    checks << flat_agents_check(agent_dir, "--claude")

    # compact-instructions block in CLAUDE.md (intent 312)
    checks << claude_compact_instructions_check(agent_dir)

    checks
  end

  # Claude CLAUDE.md marker literals. Keep in sync with
  # InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX / CLAUDE_SECTION_END (doctor does not
  # require installer_core, so the literals are duplicated, exactly as for Codex). The
  # BODY and its hash are NOT duplicated: they come from the shared CompactInstructions.
  CLAUDE_COMPACT_BEGIN_PREFIX = "<!-- BEGIN PLASTIC COMPACT"
  CLAUDE_COMPACT_END = "<!-- END PLASTIC COMPACT -->"

  # Present, well formed, and current. The Codex AGENTS.md check stops at well formed;
  # this one also compares the hash in the BEGIN marker against the shipped body, so a
  # block an older version left behind is reported rather than trusted.
  def claude_compact_instructions_check(agent_dir)
    claude_md = File.join(agent_dir, "CLAUDE.md")
    name = "claude_compact_instructions"
    hint = "Re-run the Plastic installer with --claude"

    unless File.exist?(claude_md)
      return check(category: "agent_registration", name: name, status: "fail",
                   message: "CLAUDE.md not found at #{tilde(claude_md)}, so the compaction instructions are not installed",
                   fixable: true, fix_hint: hint)
    end

    content = File.read(claude_md)
    b = content.index(CLAUDE_COMPACT_BEGIN_PREFIX)
    e = content.index(CLAUDE_COMPACT_END)
    well_formed = b && e && e > b && content[b...e].include?("-->")

    unless well_formed
      return check(category: "agent_registration", name: name, status: "fail",
                   message: "CLAUDE.md is missing the compact-instructions block or its section is malformed",
                   fixable: true, fix_hint: hint)
    end

    installed_hash = content[b..][/hash:(\w+)/, 1]
    if installed_hash != CompactInstructions.body_hash
      return check(category: "agent_registration", name: name, status: "fail",
                   message: "the compact-instructions block in CLAUDE.md is stale " \
                            "(hash:#{installed_hash}, current is hash:#{CompactInstructions.body_hash})",
                   fixable: true, fix_hint: hint)
    end

    check(category: "agent_registration", name: name, status: "pass",
          message: "CLAUDE.md carries the current compact-instructions block")
  end

  # Unfiltered classification (intent 276, spec Approach table): mode (a)
  # unowned warns, mode (b) current-but-missing fails, a retired/non-hook
  # launcher is skipped, a third-party hook stays silent.
  def hooks_entries_owned_check(settings)
    known_launchers = HookRegistry.claude_launcher_names
    unowned = []
    missing_launcher = []

    each_hook_command(settings["hooks"]) do |event, cmd|
      if HookRegistry.claude_current_command?(cmd)
        missing_launcher << "missing launcher: #{event}: #{cmd} names a file that is not on disk" unless launcher_on_disk?(cmd, known_launchers)
      elsif HookRegistry.claude_purge_command?(cmd)
        next # retired or non-hook launcher; hooks_match_registry owns this case
      elsif unowned_prefixed_command?(cmd)
        unowned << "reserved prefix: #{event}: #{cmd} is not a hook Plastic registers"
      end
    end

    hooks_entries_owned_result("hooks_entries_owned", unowned, missing_launcher,
      pass_message: "Every settings.json hook entry is Plastic's and installed, or not ours",
      rename_hint: unowned_hook_rename_hint("settings.json"),
      missing_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest --claude."
    )
  end

  # Fail on mode (b), else warn on mode (a), else pass (spec Decision 3).
  def hooks_entries_owned_result(name, unowned, missing_launcher, pass_message:, rename_hint:, missing_hint:)
    status = if !missing_launcher.empty?
               "fail"
             elsif !unowned.empty?
               "warn"
             else
               "pass"
             end

    return check(category: "agent_registration", name: name, status: "pass", message: pass_message) if status == "pass"

    clauses = []
    clauses << "#{unowned.size} #{unowned.size == 1 ? "carries" : "carry"} the reserved plastic- prefix without being Plastic's" unless unowned.empty?
    clauses << "#{missing_launcher.size} #{missing_launcher.size == 1 ? "names" : "name"} a launcher missing from disk" unless missing_launcher.empty?

    hints = []
    hints << rename_hint unless unowned.empty?
    hints << missing_hint unless missing_launcher.empty?

    check(
      category: "agent_registration", name: name, status: status,
      message: clauses.join("; "),
      details: unowned + missing_launcher,
      fixable: true, fix_hint: hints.join(" ")
    )
  end

  def flat_skills_check(agent_dir, installer_flag)
    skills_root = File.join(agent_dir, "skills")
    found = Dir.glob(File.join(skills_root, "plastic-*", "SKILL.md"))

    if !found.empty?
      check(
        category: "agent_registration", name: "skills_exist", status: "pass",
        message: "#{found.size} plastic-* skill(s) installed in #{tilde(skills_root)}"
      )
    else
      check(
        category: "agent_registration", name: "skills_exist", status: "fail",
        message: "No plastic-* skills found in #{tilde(skills_root)}",
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest #{installer_flag}"
      )
    end
  end

  # Manifest-diff stray-skill check (intent 158a), extended (intent 276) to
  # never vanish on a missing manifest and to name the reserved-prefix rule.
  def stray_skills_check(agent_dir, installer_flag, manifest_path)
    skills_root = File.join(agent_dir, "skills")
    installed = Dir.glob(File.join(skills_root, "plastic-*", "SKILL.md"))
                    .map { |f| File.basename(File.dirname(f)) }
    manifest = read_json_safe(manifest_path)
    files = manifest.is_a?(Hash) ? manifest["files"] : nil

    if !files.is_a?(Hash) && installed.empty?
      return check(category: "agent_registration", name: "stray_skills", status: "pass",
        message: "No plastic-* skills installed in #{tilde(skills_root)}; nothing to verify")
    elsif !files.is_a?(Hash)
      return check(
        category: "agent_registration", name: "stray_skills", status: "warn",
        message: "#{installed.size} plastic-* skill dir(s) installed but the manifest at " \
                 "#{tilde(manifest_path)} is missing or unusable, so ownership cannot be verified",
        details: installed.sort, fixable: true,
        fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest #{installer_flag}"
      )
    end

    tracked = files.keys.select { |p| p.start_with?("#{skills_root}/") }
                   .map { |p| p.sub("#{skills_root}/", "").split("/").first }.uniq
    strays = (installed - tracked).sort
    return check(category: "agent_registration", name: "stray_skills", status: "pass",
      message: "No stray plastic-* skill directories in #{tilde(skills_root)}") if strays.empty?

    check(
      category: "agent_registration", name: "stray_skills", status: "warn",
      message: "#{strays.size} installed skill dir(s) are not skills Plastic shipped",
      details: strays, fixable: true,
      fix_hint: "The plastic- prefix is reserved for hooks and skills Plastic ships: rename a skill " \
                "of your own that carries it, or re-run the installer (npx @zalom/plastic@latest " \
                "#{installer_flag}) to clear a genuine leftover."
    )
  end

  def flat_agents_check(agent_dir, installer_flag)
    agents_root = File.join(agent_dir, "agents")
    found = Dir.glob(File.join(agents_root, "plastic-*.md"))

    if !found.empty?
      check(
        category: "agent_registration", name: "agents_exist", status: "pass",
        message: "#{found.size} plastic-* agent(s) installed in #{tilde(agents_root)}"
      )
    else
      check(
        category: "agent_registration", name: "agents_exist", status: "fail",
        message: "No plastic-* agents found in #{tilde(agents_root)}",
        fixable: true, fix_hint: "Re-run the Plastic installer: npx @zalom/plastic@latest #{installer_flag}"
      )
    end
  end

  def check_flat_skills_and_stray(agent_key, agent_dir)
    checks = []

    # For codex/hermes: just check skills exist (no settings.json hooks)
    checks << flat_skills_check(agent_dir, "--#{agent_key}")

    # stray_skills — installed plastic-* skill dir with no manifest entry (a leftover,
    # e.g. an old-name copy after a rename; intent 158a AC15)
    checks << stray_skills_check(agent_dir, "--#{agent_key}", File.join(agent_dir, "plastic", "manifest.json"))

    checks
  end

  def check_generic_agent_registration(agent_key, agent_dir)
    checks = check_flat_skills_and_stray(agent_key, agent_dir)
    checks << flat_agents_check(agent_dir, "--#{agent_key}")   # hermes: unchanged (.md copy)
    checks
  end

  # Codex marker literals. Keep in sync with InstallerCore::CODEX_SECTION_BEGIN_PREFIX /
  # CODEX_SECTION_END (doctor does not require installer_core, so the literals are duplicated).
  CODEX_SECTION_BEGIN_PREFIX = "<!-- BEGIN PLASTIC INTEGRATION"
  CODEX_SECTION_END = "<!-- END PLASTIC INTEGRATION -->"

  def check_codex_registration(agent_key, agent_dir)
    config = agents[agent_key]
    checks = check_flat_skills_and_stray(agent_key, agent_dir)
    checks << codex_agents_toml_check(config)

    agents_md = File.join(config[:home_dir], "AGENTS.md")

    if !File.exist?(agents_md)
      checks << check(
        category: "agent_registration", name: "codex_agents_md", status: "fail",
        message: "Codex AGENTS.md not found at #{tilde(agents_md)}",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    else
      content = File.read(agents_md)
      b = content.index(CODEX_SECTION_BEGIN_PREFIX)
      e = content.index(CODEX_SECTION_END)
      well_formed = b && e && e > b && content[b...e].include?("-->")
      if well_formed
        checks << check(
          category: "agent_registration", name: "codex_agents_md", status: "pass",
          message: "Codex AGENTS.md carries the Plastic section"
        )
      else
        checks << check(
          category: "agent_registration", name: "codex_agents_md", status: "fail",
          message: "Codex AGENTS.md is missing or has a malformed Plastic section",
          fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
        )
      end
    end

    hooks_check = codex_hooks_registered_check(config)
    checks << hooks_check
    codex_hooks_entries_owned_check(config).tap { |c| checks << c if c }
    checks << codex_hooks_implemented_check(config)
    checks << codex_hook_trust_advisory_check if hooks_check[:status] == "pass"
    codex_config_toml_advisory_check(config).tap { |c| checks << c if c }
    codex_version_floor_check(config).tap { |c| checks << c if c }

    checks
  end

  # Hooks being REGISTERED (hooks.json content matches HookRegistry) is not
  # the same as hooks being TRUSTED: Codex gates every non-managed hook
  # command behind a human /hooks review, keyed by the command's current
  # hash, so a release that changes a hook command re-arms the review
  # (intent 198, Decision D2). Whether Codex persists a queryable trust
  # record anywhere under ~/.codex is undocumented and unverified, so this
  # can never be a real pass or fail on trust state; it is an advisory that
  # always names the /hooks step, and it fires only once hooks are actually
  # registered (an unregistered hook is already reported by
  # codex_hooks_registered_check, so reminding about trust on top of that
  # would be noise, not signal).
  def codex_hook_trust_advisory_check
    check(
      category: "agent_registration", name: "codex_hooks_trust", status: "warn",
      message: "Open Codex, run /hooks, and trust the Plastic hook definitions. " \
               "Codex re-arms this review whenever a hook's command changes.",
      fixable: false
    )
  end

  # Codex-specific agent presence + structural sanity: ~/.codex/agents/plastic-*.toml
  # exist and each carries the mandatory fields. No TOML parser (doctor depends on none):
  # "structural" means the mandatory keys appear as lines and the multi-line
  # developer_instructions string is balanced (an opening triple-quote has a later one).
  def codex_agents_toml_check(config)
    agents_root = File.join(config[:home_dir], "agents")
    found = Dir.glob(File.join(agents_root, "plastic-*.toml"))

    if found.empty?
      return check(
        category: "agent_registration", name: "codex_agents_toml", status: "fail",
        message: "No plastic-* agent TOML files found in #{tilde(agents_root)}",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end

    malformed = found.reject { |f| codex_agent_toml_well_formed?(File.read(f)) }
    if malformed.empty?
      check(
        category: "agent_registration", name: "codex_agents_toml", status: "pass",
        message: "#{found.size} plastic-* agent TOML(s) installed in #{tilde(agents_root)}"
      )
    else
      check(
        category: "agent_registration", name: "codex_agents_toml", status: "fail",
        message: "#{malformed.size} Codex agent TOML(s) missing mandatory fields",
        details: malformed.map { |f| tilde(f) },
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end
  end

  def codex_agent_toml_well_formed?(content)
    marker = 'developer_instructions = """'
    di = content.index(marker)
    has_name = content.match?(/^name\s*=\s*"/)
    has_desc = content.match?(/^description\s*=\s*"/)
    balanced = di && content.index('"""', di + marker.length)
    has_name && has_desc && !di.nil? && !balanced.nil?
  end

  def codex_hooks_registered_check(config)
    hooks_json = File.join(config[:home_dir], "hooks.json")
    dispatcher = File.join(plastic_home, "scripts", "codex-hook")
    data = read_json_safe(hooks_json)

    if data.nil?
      return check(
        category: "agent_registration", name: "codex_hooks_registered", status: "fail",
        message: "Codex hooks.json missing or unreadable at #{tilde(hooks_json)}",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end

    expected = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher)
    live = data["hooks"] || {}
    missing = []
    expected.each do |event, groups|
      want = Array(groups).flat_map { |g| g["hooks"].map { |h| h["command"] } }
      got = Array(live[event]).flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
      missing.concat(want - got)
    end

    if missing.empty?
      check(
        category: "agent_registration", name: "codex_hooks_registered", status: "pass",
        message: "Codex hooks registered in hooks.json"
      )
    else
      check(
        category: "agent_registration", name: "codex_hooks_registered", status: "fail",
        message: "Codex hooks.json missing #{missing.size} command(s)",
        details: missing,
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end
  end

  # Codex sibling of hooks_entries_owned_check: mode (b) is "the dispatcher
  # is registered but scripts/codex-hook is missing" (intent 276). nil when
  # hooks.json is missing: codex_hooks_registered_check owns that state.
  def codex_hooks_entries_owned_check(config)
    data = read_json_safe(File.join(config[:home_dir], "hooks.json"))
    return nil if data.nil?

    unowned = []
    missing_dispatcher = []

    each_hook_command(data["hooks"]) do |event, cmd|
      if HookRegistry.codex_purge_command?(cmd)
        missing_dispatcher << "missing launcher: #{event}: #{cmd} names a file that is not on disk" unless launcher_on_disk?(cmd, HookRegistry::CODEX_DISPATCHER_BASENAMES)
      elsif unowned_prefixed_command?(cmd)
        unowned << "reserved prefix: #{event}: #{cmd} is not a hook Plastic registers"
      end
    end

    hooks_entries_owned_result("codex_hooks_entries_owned", unowned, missing_dispatcher,
      pass_message: "Every hooks.json entry is Plastic's and installed, or not ours",
      rename_hint: unowned_hook_rename_hint("hooks.json"),
      missing_hint: "Re-run the Plastic installer with --codex."
    )
  end

  # codex_hooks_implemented (intent 200): codex_hooks_registered_check above proves
  # hooks.json content matches what HookRegistry would emit; both sides of THAT
  # comparison come from the registry, so a pass only proves the registry agrees
  # with itself. It never looks at the actual dispatcher, so it cannot see a
  # registered gate with no real branch there (links-gate shipped exactly this way,
  # dead, in v1.4.0/intent 192, invisible to doctor and the suite until 198 found it
  # by hand), or a dispatcher branch nobody registers (bash-gate's shape, intent
  # 203, in the opposite direction). This check closes both directions at once.

  # The Codex hook names HookRegistry actually registers: the apply_patch record
  # hook (CODEX_POST_HOOKS) and the live-state hook names Codex inherits whole from
  # `events` (CODEX_LIVE_STATE_EVENTS), plus the SessionEnd close hook (intent 309,
  # CODEX_SESSION_END_HOOKS). The PreToolUse gate names left in 2.0 (intent 302). No
  # parsing needed: these are HookRegistry's own Ruby constants.
  def codex_registry_gate_names
    live_state = HookRegistry::CODEX_LIVE_STATE_EVENTS.flat_map do |event|
      HookRegistry.events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    end
    (HookRegistry::CODEX_POST_HOOKS + live_state + HookRegistry::CODEX_SESSION_END_HOOKS).uniq
  end

  def codex_dispatcher_gate_names(source)
    names = []
    %w[STATE_HOOKS].each do |const|
      m = source.match(/^#{const}\s*=\s*%w\[([^\]]*)\]/)
      names.concat(m[1].split(/\s+/)) if m
    end

    case_start = source.index(/^case gate\b/)
    if case_start
      case_body = source[case_start..-1]
      else_idx = case_body.index(/^else\b/)
      scanned = else_idx ? case_body[0...else_idx] : case_body
      names.concat(scanned.scan(/^when\s+"([^"]+)"/).flatten)
    end

    names.uniq!
    names.empty? ? nil : names
  end

  # The both-direction diff. Each mismatch becomes one detail line naming the
  # hook, the direction, the harness ("Codex"), and the concrete runtime effect,
  # never a generic "Codex hooks drift" message (D4).
  def codex_hooks_implemented_check(config)
    dispatcher_path = File.join(plastic_home, "scripts", "codex-hook")

    unless File.exist?(dispatcher_path)
      return check(
        category: "agent_registration", name: "codex_hooks_implemented", status: "fail",
        message: "scripts/codex-hook not found at #{tilde(dispatcher_path)}; cannot verify " \
                 "the Codex hook registry and dispatcher agree",
        fixable: true, fix_hint: "Re-run the Plastic installer with --codex"
      )
    end

    dispatcher_names = codex_dispatcher_gate_names(File.read(dispatcher_path))

    if dispatcher_names.nil?
      return check(
        category: "agent_registration", name: "codex_hooks_implemented", status: "fail",
        message: "Could not read any gate names out of #{tilde(dispatcher_path)}: the " \
                 "STATE_HOOKS constant and the `case gate` statement no longer " \
                 "match the shape this check expects, so the registry could not be checked " \
                 "against the real dispatcher. This is exactly the silent-pass failure this " \
                 "check exists to prevent; update codex_dispatcher_gate_names in doctor.rb " \
                 "to the file's new shape.",
        fixable: false
      )
    end

    registry_names = codex_registry_gate_names
    missing_dispatcher_branch = registry_names - dispatcher_names
    dead_branch = dispatcher_names - registry_names

    if missing_dispatcher_branch.empty? && dead_branch.empty?
      return check(
        category: "agent_registration", name: "codex_hooks_implemented", status: "pass",
        message: "Every Codex-registered gate has a scripts/codex-hook branch, and every " \
                 "dispatcher branch is registered"
      )
    end

    details = missing_dispatcher_branch.map do |name|
      "#{name} is registered in ~/.codex/hooks.json but scripts/codex-hook has no branch " \
        "for it, so it always falls through to the fail-open else and always allows the write"
    end
    details += dead_branch.map do |name|
      "#{name} has a branch in scripts/codex-hook but is not registered in HookRegistry for " \
        "Codex, so it is dead code Codex never reaches"
    end

    check(
      category: "agent_registration", name: "codex_hooks_implemented", status: "fail",
      message: "Codex's hook registry and scripts/codex-hook disagree on #{details.size} gate(s)",
      details: details,
      fixable: false
    )
  end

  def codex_config_toml_advisory_check(config)
    config_toml = File.join(config[:home_dir], "config.toml")
    return nil unless File.exist?(config_toml)

    toml = File.read(config_toml) rescue ""
    warns = []
    # guide Part 3: `codex_hooks` is a deprecated alias for `[features] hooks`; catch both.
    warns << "hooks are disabled ([features] hooks = false); Plastic hooks will not fire" if toml.match?(/^\s*(?:codex_)?hooks\s*=\s*false/)
    warns << "sandbox_mode = \"read-only\"; apply_patch writes (and the record hook) cannot run" if toml.match?(/^\s*sandbox_mode\s*=\s*["']read-only["']/)
    return nil if warns.empty?

    check(
      category: "agent_registration", name: "codex_config_advisory", status: "warn",
      message: warns.join("; "),
      fixable: false,
      fix_hint: "Set [features] hooks = true and sandbox_mode = \"workspace-write\" in ~/.codex/config.toml"
    )
  end

  # Codex version-floor advisory (intent 184): READ ONLY. The apply_patch PreToolUse
  # veto (scripts/lib/hook_registry.rb, scripts/codex-hook) only fires from Codex
  # v0.123.0 (PR #18391); below it the veto silently no-ops. version.json is Codex's
  # update-checker cache and holds no installed version, so the only install-method-
  # agnostic source is `codex --version`, shelled out through the injected runner.
  # Four honest branches (intent 208, no pass-by-construction): absent home -> nil;
  # present but undetectable -> distinct warn; below floor -> warn; at/above -> pass.
  def codex_version_floor_check(config)
    return nil unless File.exist?(config[:home_dir])

    stdout, ok = @runner.call(["--version"])
    version = ok ? codex_version_from_output(stdout) : nil
    parsed = version && safe_version(version)

    if parsed.nil?
      return check(
        category: "agent_registration", name: "codex_version_floor", status: "warn",
        message: "Could not determine the installed Codex version (`codex --version` did not " \
                 "return a parseable version); Plastic cannot confirm the apply_patch hooks " \
                 "floor v#{CODEX_HOOKS_FLOOR} is met, so its gate may silently no-op",
        fixable: false,
        fix_hint: "Ensure `codex` is on PATH and `codex --version` >= #{CODEX_HOOKS_FLOOR}"
      )
    end

    if parsed < safe_version(CODEX_HOOKS_FLOOR)
      return check(
        category: "agent_registration", name: "codex_version_floor", status: "warn",
        message: "Installed Codex #{version} predates v#{CODEX_HOOKS_FLOOR}; the apply_patch " \
                 "PreToolUse veto only exists from v#{CODEX_HOOKS_FLOOR} (PR #18391), so Plastic's " \
                 "gate silently no-ops on this install",
        fixable: false,
        fix_hint: "Upgrade Codex to v#{CODEX_HOOKS_FLOOR} or newer with your install method " \
                  "(npm i -g @openai/codex, mise, homebrew, or cargo)"
      )
    end

    check(
      category: "agent_registration", name: "codex_version_floor", status: "pass",
      message: "Codex #{version} meets the apply_patch hooks floor v#{CODEX_HOOKS_FLOOR}"
    )
  end

  def codex_version_from_output(stdout)
    m = stdout.to_s.match(/(\d+\.\d+\.\d+(?:[.\-+][0-9A-Za-z.\-+]*)?)/)
    m && m[1]
  end

  def safe_version(str)
    Gem::Version.new(str.to_s)
  rescue ArgumentError
    nil
  end

  def check_core_files(agent_key, include_drift: true)
    checks = []

    # plastic_md
    plastic_md = File.join(plastic_home, "PLASTIC.md")
    if File.exist?(plastic_md)
      checks << check(
        category: "core_files", name: "plastic_md", status: "pass",
        message: "PLASTIC.md exists"
      )
    else
      checks << check(
        category: "core_files", name: "plastic_md", status: "fail",
        message: "PLASTIC.md not found at #{tilde(plastic_md)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore core files"
      )
    end

    # version_file
    version_path = File.join(plastic_home, "VERSION")
    if File.exist?(version_path)
      checks << check(
        category: "core_files", name: "version_file", status: "pass",
        message: "VERSION file exists"
      )
    else
      checks << check(
        category: "core_files", name: "version_file", status: "fail",
        message: "VERSION file not found at #{tilde(version_path)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore core files"
      )
    end

    # scripts_present
    scripts_dir = File.join(plastic_home, "scripts")
    missing_scripts = REQUIRED_SCRIPTS.reject { |s| File.exist?(File.join(scripts_dir, s)) }

    if missing_scripts.empty?
      checks << check(
        category: "core_files", name: "scripts_present", status: "pass",
        message: "All #{REQUIRED_SCRIPTS.size} required scripts present"
      )
    else
      checks << check(
        category: "core_files", name: "scripts_present", status: "fail",
        message: "#{missing_scripts.size} required script(s) missing from #{tilde(scripts_dir)}",
        details: missing_scripts,
        fixable: true, fix_hint: "Re-run the Plastic installer to restore scripts"
      )
    end

    # scripts_executable
    if File.directory?(scripts_dir)
      script_files = Dir.children(scripts_dir)
        .map { |f| File.join(scripts_dir, f) }
        .select { |f| File.file?(f) }

      non_executable = script_files.reject { |f| File.executable?(f) }

      if non_executable.empty?
        checks << check(
          category: "core_files", name: "scripts_executable", status: "pass",
          message: "All scripts in #{tilde(scripts_dir)} are executable"
        )
      else
        checks << check(
          category: "core_files", name: "scripts_executable", status: "fail",
          message: "#{non_executable.size} script(s) not executable",
          details: non_executable.map { |f| tilde(f) },
          fixable: true, fix_hint: "chmod +x on the listed files"
        )
      end
    end

    # version_match — compare global VERSION with agent-side VERSION
    global_version = read_version
    agent_config = agents[agent_key]

    if global_version && agent_config
      agent_version_path = case agent_key
                           when "claude" then File.join(agent_config[:dir], "plastic", "VERSION")
                           else File.join(agent_config[:dir], "plastic", "VERSION")
                           end

      if File.exist?(agent_version_path)
        agent_version = File.read(agent_version_path).strip

        if global_version == agent_version
          checks << check(
            category: "core_files", name: "version_match", status: "pass",
            message: "Global VERSION (#{global_version}) matches agent-side VERSION"
          )
        else
          checks << check(
            category: "core_files", name: "version_match", status: "warn",
            message: "Version mismatch: global=#{global_version}, agent=#{agent_version}",
            details: [
              "#{tilde(File.join(plastic_home, "VERSION"))}: #{global_version}",
              "#{tilde(agent_version_path)}: #{agent_version}",
            ],
            fixable: true,
            fix_hint: "Re-sync the stale harness: npx @zalom/plastic@latest install --reinstall <flag>, or plastic-rollback to a prior version"
          )
        end
      else
        checks << check(
          category: "core_files", name: "version_match", status: "warn",
          message: "Agent-side VERSION file not found at #{tilde(agent_version_path)}",
          fixable: true,
          fix_hint: "Re-sync the stale harness: npx @zalom/plastic@latest install --reinstall <flag>, or plastic-rollback to a prior version"
        )
      end
    end

    checks += check_agent_model_drift(agent_key) if include_drift

    checks
  end

  def check_manifest_sync(agent_key)
    checks = []

    global_manifest = File.join(plastic_home, "manifest.json")
    checks << verify_manifest(global_manifest, "global")

    agent_dir = agents[agent_key][:dir]
    agent_manifest = File.join(agent_dir, "plastic", "manifest.json")
    checks << verify_manifest(agent_manifest, "agent")

    checks
  end

  # Check one manifest file. Returns a single check (pass or fail).
  def verify_manifest(manifest_path, label)
    unless File.exist?(manifest_path)
      return check(
        category: "manifest_sync", name: "#{label}_manifest", status: "fail",
        message: "#{label} core manifest missing — re-run the Plastic installer",
        details: [tilde(manifest_path)],
        fixable: true, fix_hint: "Re-run the Plastic installer"
      )
    end

    data = read_json_safe(manifest_path)
    files = data.is_a?(Hash) ? data["files"] : nil
    unless files.is_a?(Hash)
      return check(
        category: "manifest_sync", name: "#{label}_manifest", status: "fail",
        message: "#{label} core manifest unreadable or malformed — re-run the Plastic installer",
        details: [tilde(manifest_path)],
        fixable: true, fix_hint: "Re-run the Plastic installer"
      )
    end

    missing = []
    mismatched = []
    files.each do |path, recorded|
      unless File.exist?(path)
        missing << tilde(path)
        next
      end
      actual = Digest::SHA256.file(path).hexdigest
      mismatched << tilde(path) if actual != recorded
    end

    if missing.empty? && mismatched.empty?
      check(
        category: "manifest_sync", name: "#{label}_manifest", status: "pass",
        message: "#{label} manifest: all #{files.size} tracked file(s) present and matching"
      )
    else
      details = []
      details += missing.map { |p| "missing: #{p}" }
      details += mismatched.map { |p| "modified: #{p}" }
      check(
        category: "manifest_sync", name: "#{label}_manifest", status: "fail",
        message: "#{label} manifest out of sync: #{missing.size} missing, #{mismatched.size} modified",
        details: details,
        fixable: true, fix_hint: "Re-run the Plastic installer to restore tracked files"
      )
    end
  end


  # Binary core sync check: agent registration + core files (drift excluded) + manifest
  # sync + registered project paths + global store availability, rolled up with binary:
  # true so ANY warn or fail makes the overall status "fail" (and "warn" is never
  # emitted). Used by `doctor.rb --core` (219 D1/D2: operational readiness only, no
  # agent_model_drift, no store-content scanning).
  def run_core_checks(agent_key)
    all_checks = []
    all_checks += check_agent_registration(agent_key)
    all_checks += check_core_files(agent_key, include_drift: false)
    all_checks += check_manifest_sync(agent_key)
    all_checks += check_registered_project_paths
    all_checks += check_global_store_available

    summarize(all_checks, agent_key, binary: true)
  end

  def check_registered_project_paths
    checks = []

    projects_yml_path = File.join(plastic_home, "projects.yml")
    projects_data = load_yaml_safe(projects_yml_path)

    if projects_data.nil?
      checks << check(
        category: "project_stores", name: "registered_project_paths", status: "fail",
        message: "projects.yml not found or invalid at #{tilde(projects_yml_path)}",
        fixable: true, fix_hint: "Re-run the Plastic installer to restore projects.yml"
      )
      return checks
    end

    projects = projects_data["projects"]
    unless projects.is_a?(Hash) && !projects.empty?
      checks << check(
        category: "project_stores", name: "registered_project_paths", status: "pass",
        message: "No projects registered"
      )
      return checks
    end

    projects.each do |slug, project_info|
      path = project_info.is_a?(Hash) ? project_info["path"] : nil

      if path && File.directory?(path)
        checks << check(
          category: "project_stores", name: "project_path_resolves", status: "pass",
          message: "Registered path for '#{slug}' resolves to a real directory"
        )
      else
        checks << check(
          category: "project_stores", name: "project_path_resolves", status: "fail",
          message: "Registered path for '#{slug}' does not resolve to a real directory",
          details: [path ? tilde(path) : "(no path set in projects.yml)"],
          fixable: false
        )
      end
    end

    checks
  end

  # Roll a list of checks up into the standard result envelope.
  # When binary: true, the overall status is "pass" only if there are zero warn
  # AND zero fail; any warn or fail yields "fail" (never "warn"). When false
  # (the default) the classic 3-state pass/warn/fail roll-up is used.
  def summarize(all_checks, agent_key, binary: false)
    summary = { pass: 0, warn: 0, fail: 0, total: all_checks.size }
    all_checks.each { |c| summary[c[:status].to_sym] += 1 }

    overall = if binary
                (summary[:fail] > 0 || summary[:warn] > 0) ? "fail" : "pass"
              elsif summary[:fail] > 0
                "fail"
              elsif summary[:warn] > 0
                "warn"
              else
                "pass"
              end

    {
      version: read_version || "unknown",
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      status: overall,
      agent: agent_key,
      checks: all_checks,
      summary: summary,
    }
  end
end
