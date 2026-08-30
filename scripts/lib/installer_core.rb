# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"
require "digest"
require "time"
require_relative "hook_registry"
require_relative "agent_models"
require_relative "harness_text"
require_relative "compact_instructions"

# Shared installer machinery, instantiable with injected package root / store / agent
# map so the verb scripts (install/update/uninstall/rollback) and their tests can run
# hermetically (no eval, no global-constant rewriting). Mirrors the DI recipe proven in
# doctor.rb / install.rb (intents 30a, 30a1). Library only - no CLI, no $PROGRAM_NAME guard.
class InstallerCore
  DEFAULT_PLASTIC_HOME = File.join(Dir.home, ".plastic")

  DEFAULT_AGENTS = [
    { key: "claude", name: "Claude Code", dir: File.join(Dir.home, ".claude"), flag: "--claude",
      skill_prefix: "/" },
    { key: "codex", name: "Codex CLI", dir: File.join(Dir.home, ".agents"),
      home_dir: File.join(Dir.home, ".codex"), flag: "--codex", skill_prefix: "$" },
    { key: "hermes", name: "Hermes", dir: File.join(Dir.home, ".hermes"), flag: "--hermes" },
  ].freeze

  # Codex AGENTS.md marked-section markers (single source of truth; doctor.rb
  # matches these literals structurally, so keep the two in sync by hand).
  CODEX_SECTION_BEGIN_PREFIX = "<!-- BEGIN PLASTIC INTEGRATION"
  CODEX_SECTION_END = "<!-- END PLASTIC INTEGRATION -->"

  # Regex matching exactly one managed section (BEGIN line .. END line), non-greedy.
  CODEX_SECTION_RE = /^<!-- BEGIN PLASTIC INTEGRATION.*?-->\n.*?\n<!-- END PLASTIC INTEGRATION -->\n?/m

  # Claude CLAUDE.md marked-section markers (intent 312). A pair of its own, not the
  # Codex literals: the two managed files can be one file (a user who symlinks
  # ~/.claude/CLAUDE.md at ~/.codex/AGENTS.md, or the reverse), and a shared literal
  # would let one body silently replace the other and an uninstall of one strip both.
  # doctor_core.rb matches these literals structurally, so keep the two in sync by hand.
  CLAUDE_SECTION_BEGIN_PREFIX = "<!-- BEGIN PLASTIC COMPACT"
  CLAUDE_SECTION_END = "<!-- END PLASTIC COMPACT -->"
  CLAUDE_SECTION_RE = /^<!-- BEGIN PLASTIC COMPACT.*?-->\n.*?\n<!-- END PLASTIC COMPACT -->\n?/m

  # Curated essentials plus a pointer to ~/.plastic/PLASTIC.md and the plastic-conventions
  # skill, injected into ~/.codex/AGENTS.md. Not a slice of PLASTIC.md itself: AGENTS.md is
  # a shared file Codex merges from multiple sources, so this block stays a small,
  # hand-curated pointer rather than embedding the core wholesale, and it never drifts
  # because it only ever points, never duplicates.
  CODEX_AGENTS_MD_BODY = <<~MD.freeze
    Plastic is installed for this agent. Plastic is intent-driven state management: all
    work flows through an intent, moved through What, Why, How, then Exec. Do not jump
    straight to code.

    Standing rules:
    - Core conventions live in ~/.plastic/PLASTIC.md. Read it and follow it exactly. For
      depth, read a chapter from ~/.agents/skills/plastic-conventions/references/ on demand.
      Both are generated and overwritten on Plastic updates, so never edit them.
    - Operational procedures are installed as skills under ~/.agents/skills/ (each
      plastic-<name>/SKILL.md). Invoke one explicitly as $plastic-<name> (for example
      $plastic-doctor), or let Codex pick one implicitly by matching its description.
    - Intents, specs, plans, checklists, and outcomes live under ~/.plastic/, never in
      the project tree.

    This section is managed by the Plastic installer. It is replaced on update and removed
    on uninstall. Do not edit anything between the BEGIN and END markers.
  MD

  attr_reader :package_root, :plastic_home, :version, :agents

  def initialize(package_root:, plastic_home: DEFAULT_PLASTIC_HOME, version: nil, agents: DEFAULT_AGENTS)
    @package_root = package_root
    @plastic_home = plastic_home
    @version = version || read_package_version(package_root)
    @agents = agents
  end

  def read_package_version(root)
    File.read(File.join(root, "package.json")).then { |s| JSON.parse(s)["version"] }
  end

  # --- Channel derivation (the channel is encoded in the version string) ---

  # "1.0.0-alpha.18" -> "alpha", "1.2.0-beta.1" -> "beta", "1.0.0" -> "latest".
  def channel_for(version)
    case version.to_s
    when /-alpha/ then "alpha"
    when /-beta/ then "beta"
    else "latest"
    end
  end

  # Stability ranking: stable(latest) > beta > alpha. Higher = more stable.
  STABILITY = { "alpha" => 0, "beta" => 1, "latest" => 2 }.freeze

  def stability_rank(version_or_channel)
    ch = STABILITY.key?(version_or_channel) ? version_or_channel : channel_for(version_or_channel)
    STABILITY[ch] || 2
  end

  # --- Semver (§11) - parse/compare, shared by update + rollback ---

  def semver_parse(version)
    m = /\A(\d+)\.(\d+)\.(\d+)(?:-(.+))?\z/.match(version.to_s.strip)
    return nil unless m
    { maj: m[1].to_i, min: m[2].to_i, pat: m[3].to_i, pre: m[4] ? m[4].split(".") : nil }
  end

  # Returns -1, 0, 1, or nil if either side is unparseable.
  def semver_compare(a, b)
    pa = semver_parse(a)
    pb = semver_parse(b)
    return nil unless pa && pb
    %i[maj min pat].each { |k| return pa[k] <=> pb[k] unless pa[k] == pb[k] }
    return 0 if pa[:pre].nil? && pb[:pre].nil?
    return 1 if pa[:pre].nil?
    return -1 if pb[:pre].nil?
    [pa[:pre].length, pb[:pre].length].max.times do |i|
      x = pa[:pre][i]
      y = pb[:pre][i]
      return -1 if x.nil?
      return 1 if y.nil?
      xn = x.match?(/\A\d+\z/)
      yn = y.match?(/\A\d+\z/)
      if xn && yn
        return x.to_i <=> y.to_i unless x.to_i == y.to_i
      elsif xn
        return -1
      elsif yn
        return 1
      elsif x != y
        return x <=> y
      end
    end
    0
  end

  def semver_gt?(a, b)
    semver_compare(a, b) == 1
  end

  # --- versions.json ledger (append-only JSONL - one object per line) ---

  def ledger_path
    File.join(plastic_home, "versions.json")
  end

  # Append a single immutable entry. Opens in append mode; never rewrites prior lines.
  # action ∈ { install, reinstall, update, downgrade }. `harness` (intent 210, G5) names
  # which agent this row records a sync for (claude/codex/hermes); optional so a
  # core-only or pre-210 caller still writes a valid, readable row. Readers must stay
  # tolerant of legacy rows that carry no "harness" key at all.
  def ledger_append(entry_version, action, harness: nil)
    FileUtils.mkdir_p(plastic_home)
    entry = { "version" => entry_version, "action" => action, "at" => Time.now.utc.iso8601 }
    entry["harness"] = harness if harness
    File.open(ledger_path, "a") { |f| f.puts(JSON.generate(entry)) }
  end

  def ledger_read
    return [] unless File.exist?(ledger_path)
    File.readlines(ledger_path).filter_map do |raw|
      raw = raw.strip
      next if raw.empty?
      JSON.parse(raw) rescue nil
    end
  end

  # Most recent ledger entry, or nil.
  def ledger_current
    ledger_read.last
  end

  # --- Agent selection helpers (shared by install/uninstall) ---

  def agent_keys_from(argv)
    keys = []
    keys = agents.map { |a| a[:key] } if argv.include?("--all")
    argv.each do |arg|
      agent = agents.find { |a| a[:flag] == arg }
      keys << agent[:key] if agent
    end
    keys.uniq
  end

  def prompt_agents(input: $stdin)
    return ["claude"] unless input.tty?

    puts "Which agents should Plastic register for?\n\n"
    agents.each_with_index { |a, i| puts "  #{i + 1}. #{a[:name]} (#{a[:home_dir] || a[:dir]})" }
    puts "  #{agents.size + 1}. All"
    puts

    print "Select (comma-separated numbers, or Enter for Claude Code): "
    answer = input.gets&.strip || ""

    return ["claude"] if answer.empty?

    nums = answer.split(",").map { |n| n.strip.to_i }
    return agents.map { |a| a[:key] } if nums.include?(agents.size + 1)

    nums.select { |n| n >= 1 && n <= agents.size }.map { |n| agents[n - 1][:key] }
  end

  # Resolve whether install should keep the user's existing statusline or switch it
  # to Plastic's. Pure function of (settings file, argv, input, reinstall): no writes,
  # so it stays fully unit-testable apart from merge_claude_hooks.
  def statusline_choice(settings_path, argv: [], input: $stdin, reinstall: false)
    existing_command = read_json_safe(settings_path)&.dig("statusLine", "command").to_s
    return :plastic if existing_command.empty?
    return :plastic if HookRegistry.claude_purge_command?(existing_command)

    idx = argv.index("--statusline")
    flag = idx && argv[idx + 1]
    return flag.to_sym if %w[keep plastic].include?(flag)

    return :keep if reinstall
    return prompt_statusline(input: input) if input.tty?

    :keep
  end

  def prompt_statusline(input: $stdin)
    return :keep unless input.tty?

    puts "An existing statusline was found in your settings.\n\n"
    puts "  1. Keep my statusline (Plastic will not change it)"
    puts "  2. Switch to Plastic's statusline"
    puts
    print "Select (1 or 2, Enter to keep): "
    answer = input.gets&.strip

    answer == "2" ? :plastic : :keep
  end

  # --- Distribution phase ---

  def distribute(mode)
    puts "  \u{1f4e6} #{mode == :update ? "Updating" : "Installing"} core files to #{plastic_home}"

    manifest_path = File.join(plastic_home, "manifest.json")
    # Capture the prior manifest before the copy loop touches anything, so a
    # file dropped from core_files (renamed/removed) can be pruned below
    # instead of orphaning forever. Mirrors install_for_agent's prune (D14
    # Why-gate correction: this global path never had it).
    old_files = manifest_files(manifest_path)

    FileUtils.mkdir_p(plastic_home)
    FileUtils.mkdir_p(File.join(plastic_home, "scripts", "lib"))
    FileUtils.mkdir_p(File.join(plastic_home, "templates"))
    FileUtils.mkdir_p(File.join(plastic_home, "hooks"))

    core_files.each do |src, dest|
      src_path = File.join(package_root, src)
      dest_path = File.join(plastic_home, dest)
      next unless File.exist?(src_path)

      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(src_path, dest_path)
    end

    File.write(File.join(plastic_home, "VERSION"), "#{version}\n")

    Dir.glob(File.join(plastic_home, "scripts", "*")).each { |f| FileUtils.chmod(0o755, f) if File.file?(f) }
    # Same treatment for the hook launchers, and UNCONDITIONAL on update as well as install:
    # FileUtils.cp onto an existing file keeps the DESTINATION's old mode, so a copy over a
    # non-executable predecessor would stay non-executable forever and capture3 would raise
    # EACCES into the same silent fail-open this intent is closing. *.json is skipped because
    # hooks.json is a registry, not a program (same reasoning as test/rubyopt_clearing_test.rb).
    Dir.glob(File.join(plastic_home, "hooks", "*")).each do |f|
      FileUtils.chmod(0o755, f) if File.file?(f) && !f.end_with?(".json")
    end

    global_files = core_files.values.map { |d| File.join(plastic_home, d) }
    global_files << File.join(plastic_home, "VERSION")
    global_files = global_files.select { |p| File.exist?(p) }
    write_manifest(global_files, manifest_path)

    pruned = prune_removed_files(old_files - global_files, root: plastic_home)

    puts "  \u{2705} Core files synced (v#{version})#{pruned.positive? ? ", #{pruned} stale file(s) pruned" : ""}"
  end

  # Templates ship in full: every file under templates/ in the repo must reach
  # ~/.plastic/templates/ on install/update. Derived from Dir.glob so a new
  # template file added later is registered automatically, closing the
  # whack-a-mole pattern that hid templates/index.md and templates/project.yml
  # from every install for five weeks (intent 190).
  def template_files
    Dir.glob(File.join(package_root, "templates", "*")).each_with_object({}) do |path, acc|
      next unless File.file?(path)

      rel = File.join("templates", File.basename(path))
      acc[rel] = rel
    end
  end

  # Hook launchers ship in full: scripts/codex-hook resolves a live-state launcher at
  # __dir__/../hooks/<gate>, which is ~/.plastic/hooks/<gate> once installed, so the launchers
  # have to BE there or every Codex live-state hook fails open with no message (intent 249).
  # Glob-derived for the same reason template_files is: a hand-written list hid two template
  # files from every install for five weeks (intent 190), and a new hook must register itself.
  # No path rewrite on this copy, unlike install_claude's: the launchers resolve their core
  # through "$SCRIPT_DIR/../scripts/", which from ~/.plastic/hooks/ already lands on
  # ~/.plastic/scripts/. Copied whole, hooks.json and run-hook and statusline included: all
  # three are inert at that path, and an exclusion list is exactly the maintenance this avoids.
  def hook_files
    Dir.glob(File.join(package_root, "hooks", "*")).each_with_object({}) do |path, acc|
      next unless File.file?(path)

      rel = File.join("hooks", File.basename(path))
      acc[rel] = rel
    end
  end

  # Files copied into ~/.plastic on install/update. Every verb script + the shared lib
  # must be here so the installed ~/.plastic/scripts copy is self-complete (sync-guarded
  # by install_sync_test). The templates half is glob-derived (template_files above); the
  # rest stays a hand-written literal.
  def core_files
    hand_registered_files.merge(template_files).merge(hook_files)
  end

  def hand_registered_files
    {
      "PLASTIC.md" => "PLASTIC.md",
      "deprecations.yml" => "deprecations.yml",
      "config_asks.yml" => "config_asks.yml",
      "scripts/folgezettel-id" => "scripts/folgezettel-id",
      "scripts/read-config" => "scripts/read-config",
      "scripts/write-config" => "scripts/write-config",
      "scripts/select-update-target" => "scripts/select-update-target",
      "scripts/hook-session-start" => "scripts/hook-session-start",
      "scripts/hook-capture" => "scripts/hook-capture",
      "scripts/hook-record" => "scripts/hook-record",
      "scripts/hook-close" => "scripts/hook-close",
      "scripts/lib/power_tools.rb" => "scripts/lib/power_tools.rb",
      "scripts/lib/ruby_probe.rb" => "scripts/lib/ruby_probe.rb",
      "scripts/lib/agent_models.rb" => "scripts/lib/agent_models.rb",
      "scripts/lib/config_asks.rb" => "scripts/lib/config_asks.rb",
      "scripts/lib/release_guard.rb" => "scripts/lib/release_guard.rb",
      "scripts/lib/bridge.rb" => "scripts/lib/bridge.rb",
      "scripts/lib/savepoint.rb" => "scripts/lib/savepoint.rb",
      "scripts/lib/arm.rb" => "scripts/lib/arm.rb",
      "scripts/lib/lock.rb" => "scripts/lib/lock.rb",
      "scripts/plastic-lock" => "scripts/plastic-lock",
      "scripts/lib/hook_registry.rb" => "scripts/lib/hook_registry.rb",
      "scripts/lib/compact_instructions.rb" => "scripts/lib/compact_instructions.rb",
      "scripts/agent-report" => "scripts/agent-report",
      "scripts/lib/insights.rb" => "scripts/lib/insights.rb",
      "scripts/insight-append" => "scripts/insight-append",
      "scripts/lib/worktree.rb" => "scripts/lib/worktree.rb",
      "scripts/lib/boot_banner.rb" => "scripts/lib/boot_banner.rb",
      "scripts/lib/dashboard_banner.rb" => "scripts/lib/dashboard_banner.rb",
      "scripts/lib/qmd_sync.rb" => "scripts/lib/qmd_sync.rb",
      "scripts/qmd-sync" => "scripts/qmd-sync",
      "scripts/lib/roadmap_savepoint.rb" => "scripts/lib/roadmap_savepoint.rb",
      "scripts/roadmap-savepoint" => "scripts/roadmap-savepoint",
      "scripts/lib/roadmap_queue.rb" => "scripts/lib/roadmap_queue.rb",
      "scripts/roadmap-next" => "scripts/roadmap-next",
      "scripts/lib/intent_validator.rb" => "scripts/lib/intent_validator.rb",
      "scripts/lib/graph_rebuild.rb" => "scripts/lib/graph_rebuild.rb",
      "scripts/lib/store_discovery.rb" => "scripts/lib/store_discovery.rb",
      "scripts/lib/frontmatter_writer.rb" => "scripts/lib/frontmatter_writer.rb",
      "scripts/lib/links_projection.rb" => "scripts/lib/links_projection.rb",
      "scripts/lib/links_section.rb" => "scripts/lib/links_section.rb",
      "scripts/lib/link_suggestions.rb" => "scripts/lib/link_suggestions.rb",
      "scripts/project-links" => "scripts/project-links",
      "scripts/link-suggest" => "scripts/link-suggest",
      "scripts/rebuild-graph" => "scripts/rebuild-graph",
      "scripts/lib/restore_intent_v1.rb" => "scripts/lib/restore_intent_v1.rb",
      "scripts/restore-intent-v1" => "scripts/restore-intent-v1",
"scripts/lib/revisions_writer.rb" => "scripts/lib/revisions_writer.rb",
"scripts/maintenance-run" => "scripts/maintenance-run",
"scripts/lib/maintenance_git.rb" => "scripts/lib/maintenance_git.rb",
"scripts/lib/worktree_sweep.rb" => "scripts/lib/worktree_sweep.rb",
"scripts/sweep-store-worktrees" => "scripts/sweep-store-worktrees",
      "scripts/validate-intent" => "scripts/validate-intent",
      "scripts/new-intent" => "scripts/new-intent",
      "scripts/end-intent" => "scripts/end-intent",
      "scripts/lib/apply_patch_envelope.rb" => "scripts/lib/apply_patch_envelope.rb",
      "scripts/lib/harness_text.rb" => "scripts/lib/harness_text.rb",
      "scripts/codex-hook" => "scripts/codex-hook",
      "scripts/spawn-preamble" => "scripts/spawn-preamble",
      "scripts/lib/store_provisioning.rb" => "scripts/lib/store_provisioning.rb",
      "scripts/provision-project-store" => "scripts/provision-project-store",
      "scripts/lib/project_validator.rb" => "scripts/lib/project_validator.rb",
      "scripts/validate-project" => "scripts/validate-project",
      "scripts/lib/installer_core.rb" => "scripts/lib/installer_core.rb",
      "scripts/lib/preflight.rb" => "scripts/lib/preflight.rb",
      "scripts/install.rb" => "scripts/install.rb",
      "scripts/update.rb" => "scripts/update.rb",
      "scripts/uninstall.rb" => "scripts/uninstall.rb",
      "scripts/rollback.rb" => "scripts/rollback.rb",
      "scripts/lib/outcome_guard.rb" => "scripts/lib/outcome_guard.rb",
      "scripts/lib/scaffold_intent.rb" => "scripts/lib/scaffold_intent.rb",
      "scripts/lib/backfill_intent.rb" => "scripts/lib/backfill_intent.rb",
      "scripts/scaffold-intent" => "scripts/scaffold-intent",
      "scripts/lib/verify_intent.rb" => "scripts/lib/verify_intent.rb",
      "scripts/verify-intent" => "scripts/verify-intent",
      "scripts/lib/exec_worktree.rb" => "scripts/lib/exec_worktree.rb",
      "scripts/exec-worktree" => "scripts/exec-worktree",
      "scripts/doctor.rb" => "scripts/doctor.rb",
      "scripts/lib/doctor_core.rb" => "scripts/lib/doctor_core.rb",
      "scripts/lib/rule_catalog.rb" => "scripts/lib/rule_catalog.rb",
      "scripts/lib/doctor_exclusions.rb" => "scripts/lib/doctor_exclusions.rb",
      "scripts/lib/doctor_session_ledger.rb" => "scripts/lib/doctor_session_ledger.rb",
      "scripts/dashboard.rb" => "scripts/dashboard.rb",
      "scripts/skill-lint" => "scripts/skill-lint",
      "scripts/lib/skill_lint.rb" => "scripts/lib/skill_lint.rb",
      "scripts/feedback-report" => "scripts/feedback-report",
      "scripts/lib/feedback_report.rb" => "scripts/lib/feedback_report.rb",
      "scripts/append-ledger" => "scripts/append-ledger",
      "scripts/lib/session_ledger.rb" => "scripts/lib/session_ledger.rb",
      "scripts/session-commit" => "scripts/session-commit",
      "scripts/file-session-intent" => "scripts/file-session-intent",
      "scripts/promote-session-item" => "scripts/promote-session-item",
      "scripts/lib/session_backfill.rb" => "scripts/lib/session_backfill.rb",
      "scripts/lib/session_close.rb" => "scripts/lib/session_close.rb",
      "scripts/lib/session_git.rb" => "scripts/lib/session_git.rb",
    }
  end

  def bootstrap
    puts "  \u{1f331} First install \u{2014} bootstrapping store..."

    FileUtils.mkdir_p(File.join(plastic_home, "store"))
    FileUtils.mkdir_p(File.join(plastic_home, "projects"))

    write_if_missing(File.join(plastic_home, "config.yml"), <<~YAML)
      version: 3
      execution_mode: subagent-driven
      stale_threshold_days: 3
      context_offer_tokens: 350000
      context_insist_tokens: 500000
      hash_length: 6
      hash_algorithm: sha256-base36
      max_slug_words: 5
      agent:
        type: claude-code
        parallel_mode: agent-teams
    YAML

    write_if_missing(File.join(plastic_home, "projects.yml"), "---\nprojects: {}\n")

    write_if_missing(File.join(plastic_home, "INDEX.md"), <<~MD)
      # Index

      ## Active

      ## Future

      ## Clusters

      ## Abandoned

      ## Completed
    MD

    write_if_missing(File.join(plastic_home, "AGENTS.md"), <<~MD)
      # Plastic: Agent Instructions

      Read `PLASTIC.md` in this directory for the core conventions; deeper doctrine lives
      in the `plastic-conventions` skill's chapters. Follow it exactly. Never modify it:
      it is overwritten on plugin updates.

      This file (`AGENTS.md`) is where project-specific rules live.

      ---
    MD

    puts "  \u{2705} Store bootstrapped"
  end

  # --- Agent adapters ---

  # Uniform per-agent install record dir: <agent-dir>/plastic/ holds VERSION and
  # manifest.json for every agent (intent 210, D2). Claude already used this; Codex
  # and Hermes are migrated onto it so one rule covers all agents and doctor's existing
  # version_match probe (<dir>/plastic/VERSION) lands on it.
  def record_dir_for(config)
    File.join(config[:dir], "plastic")
  end

  def legacy_manifest_path_for(config)
    File.join(config[:dir], "plastic-manifest.json")
  end

  def manifest_path_for(_key, config)
    File.join(record_dir_for(config), "manifest.json")
  end

  def manifest_files(manifest_path)
    return [] unless File.exist?(manifest_path)
    data = JSON.parse(File.read(manifest_path)) rescue {}
    (data["files"] || {}).keys
  end

  # Per-agent registration probe (intent 198, D7 follow-up). `installed?` in
  # install.rb only answers "is Plastic core installed at all", which cannot
  # tell two harnesses apart: once core is present, install.rb's old gate
  # refused to add ANY new harness, even one that had never been touched. This
  # asks the narrower, correct question, "has Plastic already registered
  # files for THIS agent", using the signal already tracked for prune-on-update:
  # the per-agent manifest (manifest_path_for). A missing manifest file, or a
  # manifest whose "files" list is empty (write_manifest still writes one when
  # nothing was installed), both mean nothing is registered for this agent yet.
  # An unknown key is never "installed" (fail toward proceeding, since a caller
  # that already validated the key gets its own "Unknown agent" result from
  # install_for_agent).
  def agent_installed?(key)
    config = agent_config(key)
    return false unless config
    !manifest_files(manifest_path_for(key, config)).empty?
  end

  # Agent keys whose per-agent record exists (intent 210, D2): folder-with-VERSION =
  # registered. Reads the record, never a written config list. Fail-open: an unreadable
  # record is simply "not installed" here (doctor reports integrity separately).
  def installed_agents
    agents.select { |a| File.exist?(File.join(record_dir_for(a), "VERSION")) }.map { |a| a[:key] }
  end

  def agent_version_for(config)
    path = File.join(record_dir_for(config), "VERSION")
    File.exist?(path) ? File.read(path).strip : nil
  end

  def install_for_agent(key, force, argv: [], input: $stdin, reinstall: false)
    config = agent_config(key)
    return { agent: config[:name], success: false, reason: "Unknown agent" } unless config

    # Presence probe (intent 198, Decision D1): an agent that declares its own
    # home directory (Codex, home_dir: ~/.codex) is checked THERE, because
    # config[:dir] (~/.agents) is the shared cross-tool skills root, not
    # anything Codex itself creates. A fresh Codex install has no ~/.agents
    # yet, so testing config[:dir] aborted a genuinely-present Codex. Claude
    # and Hermes declare no home_dir, so presence_dir resolves to config[:dir]
    # exactly as before and their behavior is unchanged. The failure message
    # reuses the same resolved directory, so it always names the directory
    # actually tested. install_codex still needs config[:dir] to exist by the
    # time it writes skills; install_skills_flat and generate_codex_agents
    # already FileUtils.mkdir_p their own nested paths under config[:dir] and
    # config[:home_dir], so a fresh install creates it as a side effect (no
    # separate top-level mkdir_p is required here).
    presence_dir = config[:home_dir] || config[:dir]
    unless File.directory?(presence_dir)
      return { agent: config[:name], success: false, reason: "#{presence_dir} not found, #{config[:name]} not installed?" }
    end

    # Capture the prior manifest so we can prune files that no longer ship
    # (renamed/removed skills) after a re-copy. This gives leftover-free updates.
    # Union in the legacy flat manifest's files too (intent 210, Codex migration): an
    # agent still on the pre-migration <dir>/plastic-manifest.json record tracked files
    # the new per-agent manifest never lists, so without the union prune would miss them.
    old_files = manifest_files(manifest_path_for(key, config))
    legacy_path = legacy_manifest_path_for(config)
    old_files |= manifest_files(legacy_path) if File.exist?(legacy_path) && legacy_path != manifest_path_for(key, config)

    result = case key
             when "claude" then install_claude(config, force, argv: argv, input: input, reinstall: reinstall)
             when "codex" then install_codex(config, force)
             when "hermes" then install_hermes(config, force)
             end

    new_files = manifest_files(manifest_path_for(key, config))
    pruned = prune_removed_files(old_files - new_files,
                                  root: [config[:dir], config[:home_dir], *shared_fragment_prune_roots])
    result[:pruned] = pruned if pruned.positive?

    # The legacy manifest is fully superseded once the new one is written; delete it so
    # the migration is one-shot (intent 210, D2).
    if File.exist?(legacy_path) && legacy_path != manifest_path_for(key, config)
      File.delete(legacy_path)
    end

    result
  end

  # --- Per-agent transaction with auto-restore (intent 210, D3) ---

  def backup_dir_for(config)
    File.join(plastic_home, "backups", config[:key])
  end

  # Snapshot the agent's currently manifest-listed files, PLUS the manifest itself (so
  # a restore puts the manifest and the files it describes back in sync; otherwise a
  # restored file set would be checked against the just-written NEW manifest and fail
  # verification all over again), into the backup dir, mirroring their absolute paths
  # under it. Replaces any prior snapshot (one snapshot kept, D3). Returns the list of
  # (source_abs) files snapshotted.
  def snapshot_agent(config)
    dir = backup_dir_for(config)
    FileUtils.rm_rf(dir)
    manifest_path = manifest_path_for(config[:key], config)
    files = manifest_files(manifest_path)
    files |= [manifest_path] if File.exist?(manifest_path)
    files.each do |f|
      next unless File.exist?(f)
      dest = File.join(dir, f) # f is absolute; File.join keeps the tree distinct per agent
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(f, dest)
    end
    files
  end

  # Restore the snapshot back over the live tree for this agent (auto-restore, D3/D4).
  def restore_agent(config)
    dir = backup_dir_for(config)
    Dir.glob(File.join(dir, "**", "*")).each do |src|
      next unless File.file?(src)
      dest = src.sub(dir, "")
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(src, dest)
    end
  end

  # True when every file listed in the agent manifest exists on disk with the recorded
  # hash. A missing or mismatched listed file is the falsifiable failure that triggers
  # auto-restore (intent 210, G4/G8).
  def verify_agent_manifest(config)
    path = manifest_path_for(config[:key], config)
    return false unless File.exist?(path)
    data = JSON.parse(File.read(path)) rescue {}
    files = data["files"] || {}
    return false if files.empty?
    files.all? { |f, h| File.exist?(f) && Digest::SHA256.file(f).hexdigest == h }
  end

  # Per-agent transaction (intent 210, D3): snapshot -> apply -> verify -> auto-restore on
  # failure. Forward-fix: a failure here never touches other agents. On a fresh install
  # (no prior manifest) verify-failure prunes the partial write instead of restoring.
  def transactional_install_for_agent(key, force, argv: [], input: $stdin, reinstall: false)
    config = agent_config(key)
    return { agent: key, success: false, reason: "Unknown agent" } unless config

    from_version = agent_version_for(config)
    had_record = !manifest_files(manifest_path_for(key, config)).empty?
    snapshot_agent(config) if had_record

    result = install_for_agent(key, force, argv: argv, input: input, reinstall: reinstall)

    if result[:success] && !verify_agent_manifest(config)
      if had_record
        restore_agent(config)
        result = { agent: config[:name], success: false, reason: "verify failed - restored prior snapshot" }
      else
        prune_removed_files(manifest_files(manifest_path_for(key, config)),
                             root: [config[:dir], config[:home_dir], *shared_fragment_prune_roots])
        result = { agent: config[:name], success: false, reason: "verify failed - partial install pruned" }
      end
    end
    result[:from_version] = from_version
    result[:to_version] = agent_version_for(config)
    result
  end

  # Delete tracked files present in the old manifest but absent from the new one,
  # then remove any now-empty skill directories they lived in.
  #
  # `root:` is a mandatory containment boundary (intent 223 F5): every manifest path
  # is read back from JSON written by write_manifest and could, on a hand-edited or
  # otherwise corrupt manifest, name a path outside the install this call is pruning
  # (for example `distribute` prunes against `~/.plastic/`, `install_for_agent` prunes
  # against one agent's own directories). Accepts a single path or an array (an agent
  # with a two-root schema, like Codex's `dir` plus `home_dir`, tracks files under
  # both, so a single boundary would wrongly reject legitimate prunes under the root
  # not passed). A candidate that resolves outside every given root is skipped and
  # never deleted, so a stray manifest entry can never delete a path outside the
  # target home.
  def prune_removed_files(stale_files, root:)
    expanded_roots = Array(root).compact.map { |r| File.expand_path(r) }
    removed = 0
    dirs = []
    stale_files.each do |f|
      if path_contained?(f, store_roots)
        warn "  \u{26a0}\u{fe0f}  Refused to prune #{f}: inside the intent store"
        next
      end
      unless path_contained?(f, expanded_roots)
        warn "  \u{26a0}\u{fe0f}  Skipped prune of #{f}: outside #{expanded_roots.join(", ")}"
        next
      end
      if File.exist?(f)
        File.delete(f)
        removed += 1
      end
      dirs << File.dirname(f)
    end
    dirs.uniq.sort_by { |d| -d.length }.each do |d|
      FileUtils.rmdir(d) if File.directory?(d) && Dir.empty?(d)
    end
    removed
  end

  # True when `path`, once expanded, is one of `roots` itself or lives underneath
  # one of them. String-prefix containment guarded by a trailing separator so a
  # sibling directory that merely shares a prefix (`/home/x-evil` vs root `/home/x`)
  # never counts as contained.
  def path_contained?(path, roots)
    expanded = File.expand_path(path)
    Array(roots).any? { |root| expanded == root || expanded.start_with?(root + File::SEPARATOR) }
  end

  # Intent 223 (post-delivery hardening): the user's entire intent history lives under
  # `plastic_home/store` (the global store) and `plastic_home/projects` (every project
  # store). `distribute` legitimately prunes with `root: plastic_home`, which CONTAINS
  # both directories, so the ordinary `root:` containment check in `prune_removed_files`
  # admits a store path instead of refusing it. Today that branch is unreachable (the
  # pruned set is always `old_files - global_files`, both derived from `core_files` plus
  # `VERSION`, so no store path can ever appear there), so this is defense in depth for
  # an unreachable case, not a fix for a live bug. It exists because the standing rule is
  # that NO path ever deletes the global or project intent stores, and the cost of being
  # wrong (irreversible loss of the user's whole intent history) warrants a guard that
  # fails milder than the bug it prevents, independent of what any caller's `root:` is or
  # what a hand-edited manifest claims.
  def store_roots
    [File.join(plastic_home, "store"), File.join(plastic_home, "projects")].map { |p| File.expand_path(p) }
  end

  # `install_skills_flat` relocates any top-level underscore-prefixed markdown
  # fragment (today: `_decision-tables.md`) out of the
  # per-agent skills tree and into `plastic_home` directly, then lists them in
  # `installed`, so they are manifest-tracked and eligible for prune. But
  # `install_for_agent`'s prune roots are `[config[:dir], config[:home_dir]]`,
  # which do not cover `plastic_home`, so those two files could never actually be
  # pruned (every attempt printed "Skipped prune of ... outside ..." to stderr).
  #
  # Fix scope (intent 223 N3): add each shared fragment's exact FILE path as its
  # own containment root, never `plastic_home` itself as a directory root.
  # `path_contained?` only matches a candidate that equals a root exactly or
  # lives under `root + separator`; a root that is itself a file path can never
  # have children, so listing these exact files as roots permits pruning ONLY
  # those files, never anything else under `plastic_home`. This keeps
  # `~/.plastic/store` and `~/.plastic/projects` (the user's intent stores, never
  # prunable by standing rule) outside every prune root.
  def shared_fragment_prune_roots
    skills_source = File.join(package_root, "skills")
    return [] unless File.directory?(skills_source)
    Dir.children(skills_source).select { |e| e.start_with?("_") && e.end_with?(".md") }
       .map { |e| File.join(plastic_home, e) }
  end

  def install_claude(config, force, argv: [], input: $stdin, reinstall: false)
    hooks_dir = File.join(config[:dir], "hooks")
    skills_root = File.join(config[:dir], "skills")
    plastic_dir = File.join(config[:dir], "plastic")

    FileUtils.mkdir_p(hooks_dir)
    FileUtils.mkdir_p(skills_root)
    FileUtils.mkdir_p(plastic_dir)

    installed = []

    # Copy hooks, rewriting script paths for the installed location
    hook_source = File.join(package_root, "hooks")
    Dir.glob(File.join(hook_source, "*")).each do |f|
      next unless File.file?(f)
      basename = File.basename(f)
      next if %w[hooks.json run-hook].include?(basename)
      dest_name = basename.start_with?("plastic-") ? basename : "plastic-#{basename}"
      dest = File.join(hooks_dir, dest_name)
      content = File.read(f)
      content = content.gsub('$SCRIPT_DIR/../scripts/', '$HOME/.plastic/scripts/')
      File.write(dest, content)
      FileUtils.chmod(0o755, dest)
      installed << dest
    end

    # Copy skills as flat, hyphen-namespaced personal skills (plastic-<name>/).
    # advisor.enabled: false skips the agent-advisor skill along with both
    # advisor agents below, so a user who declined the advisor never sees a
    # dead-end skill pointing at nothing installed.
    skills_source = File.join(package_root, "skills")
    skill_exclude = advisor_enabled? ? [] : ["agent-advisor"]
    installed += install_skills_flat(skills_source, skills_root, exclude: skill_exclude) if File.directory?(skills_source)

    # Copy agent role files into <dir>/agents (manifest-tracked, pruned on update)
    installed += install_agents(File.join(config[:dir], "agents"), models: agent_model_overrides, advisor_enabled: advisor_enabled?)

    # Write VERSION
    version_file = File.join(plastic_dir, "VERSION")
    File.write(version_file, "#{version}\n")
    installed << version_file

    # Remove any prior plugin/marketplace install so the layouts don't coexist
    migrate_legacy_plugin(config[:dir])

    # Merge hooks + statusline into settings.json (no plugin registration)
    settings_path = File.join(config[:dir], "settings.json")
    choice = statusline_choice(settings_path, argv: argv, input: input, reinstall: reinstall)
    merge_claude_hooks(settings_path, choice: choice)

    # Instruction injection (intent 312): the compact-instructions block into
    # ~/.claude/CLAUDE.md. A partial-ownership user file, so it is NOT manifest-tracked
    # (stripped surgically on uninstall), the same treatment ~/.codex/AGENTS.md gets.
    inject_claude_compact_md(File.join(config[:dir], "CLAUDE.md"))

    # Write manifest
    manifest_path = File.join(plastic_dir, "manifest.json")
    write_manifest(installed, manifest_path)

    { agent: config[:name], success: true, files: installed.size }
  end

  def install_codex(config, force)
    FileUtils.mkdir_p(record_dir_for(config))

    installed = []
    skills_source = File.join(package_root, "skills")
    skill_exclude = advisor_enabled? ? [] : ["agent-advisor"]
    # Intent 239: Codex is the one harness that gets its instruction text projected at
    # copy time. skill_names comes from the real skills/ listing, so the rewrite table
    # maintains itself as skills are added and renamed. Every OTHER install path passes
    # no transform and keeps the byte-for-byte copy.
    skill_names = Dir.children(skills_source).select { |e| File.directory?(File.join(skills_source, e)) }
    codex_transform = lambda do |content, rel|
      HarnessText.for_codex(content, rel_path: rel, skill_names: skill_names)
    end
    installed += install_skills_flat(skills_source, File.join(config[:dir], "skills"),
                                     exclude: skill_exclude, transform: codex_transform) if File.directory?(skills_source)
    # Codex-scoped overrides only (agents.models.codex.*): a literal Claude
    # model id set under agents.models.claude.* (or the legacy flat form,
    # which resolves as claude) must never reach a Codex TOML.
    installed += generate_codex_agents(File.join(config[:home_dir], "agents"), models: agent_model_overrides(harness: "codex"))

    # Instruction injection (L1): Plastic standing conventions into ~/.codex/AGENTS.md.
    # Partial-ownership file, so it is NOT manifest-tracked (stripped surgically on uninstall).
    FileUtils.mkdir_p(config[:home_dir])
    inject_codex_agents_md(File.join(config[:home_dir], "AGENTS.md"))

    # L3 hooks (intent 102): register into ~/.codex/hooks.json (user scope, defeats the
    # worktree bug). Partial-ownership file, so it is merged and NOT manifest-tracked
    # (stripped surgically on uninstall), same treatment as AGENTS.md.
    merge_codex_hooks(File.join(config[:home_dir], "hooks.json"))

    # Uniform per-agent record (intent 210, D2): write VERSION alongside the manifest,
    # the same shape install_claude already writes.
    version_file = File.join(record_dir_for(config), "VERSION")
    File.write(version_file, "#{version}\n")
    installed << version_file

    write_manifest(installed, manifest_path_for("codex", config))
    { agent: config[:name], success: true, files: installed.size }
  end

  # --- Codex agent TOML generation (intent 102a) ---
  #
  # Codex reads standalone TOML agent files at ~/.codex/agents/*.toml (config[:home_dir]),
  # never the ~/.agents/agents/*.md copy the shared install_agents writes (that root is
  # the cross-tool skills standard, not an agents root). The codex leg therefore generates
  # a whole-file, Plastic-owned .toml per repo agents/*.md instead of copying markdown.
  # The returned paths append to `installed`, so they are manifest-tracked and pruned on
  # uninstall by the manifest whole-file-delete path, exactly like ~/.claude/agents/*.md.
  def generate_codex_agents(agents_root, models: {})
    sources = Dir.glob(File.join(package_root, "agents", "*.md"))
    return [] if sources.empty?

    FileUtils.mkdir_p(agents_root)
    sources.filter_map do |src|
      basename = File.basename(src, ".md")
      # Codex advisor support is out of scope for this release (intent 185): the
      # owner has not evaluated the Codex reasoning-model ecosystem long enough to
      # judge it. Skip every AgentModels::CONSULTATION_AGENTS file (both
      # plastic-advisor and plastic-faux-advisor) by name, a deliberate and
      # mechanical scope cut tracked at intent 186 (Codex advisor evaluation), not
      # a permanent exclusion and not conditioned on any frontmatter or override
      # value.
      next if AgentModels::CONSULTATION_AGENTS.include?(basename)

      dest = File.join(agents_root, "#{basename}.toml")
      write_text_atomic(dest, render_codex_agent_toml(src, models[basename]))
      dest
    end
  end

  # Render one repo agents/*.md into a deterministic Codex agent TOML document. Fixed field
  # order (name, description, the model field(s) from codex_model_fields, developer_instructions)
  # so regenerate is byte-identical (idempotency).
  def render_codex_agent_toml(source_path, override)
    front, body = split_frontmatter(File.read(source_path))
    name = (front["name"] || File.basename(source_path, ".md")).to_s
    description = (front["description"] || "").to_s
    effective = (override && !override.to_s.empty? ? override : front["model"]).to_s

    parts = []
    parts << %(name = "#{toml_inline_escape(name)}")
    parts << %(description = "#{toml_inline_escape(description)}")
    parts << codex_model_fields(effective)
    parts << "developer_instructions = \"\"\"\n#{toml_ml_escape(body.strip)}\n\"\"\""
    parts.reject(&:empty?).join("\n") + "\n"
  end

  # Split a Plastic agent .md into [frontmatter_hash, body]. Tolerant: a file with no
  # frontmatter yields [{}, whole content].
  def split_frontmatter(content)
    if content =~ /\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m
      front = YAML.safe_load($1) rescue {}
      front = {} unless front.is_a?(Hash)
      [front, $2]
    else
      [{}, content]
    end
  end

  # The model-selection line(s). A known tier alias (opus/sonnet/haiku) emits BOTH a `model` line
  # (from AgentModels.codex_model_for, the intent-186 per-role Codex identity) and a
  # model_reasoning_effort line, model first for deterministic byte-identical regenerate. Any other
  # non-empty value is a literal Codex model id emitted verbatim as `model` only. Empty -> no line
  # (the agent inherits the session default). If an alias somehow lacks a mapped model, the effort
  # line still emits alone (backward-safe).
  def codex_model_fields(effective)
    return "" if effective.nil? || effective.to_s.empty?
    effort = AgentModels.effort_for(effective)
    if effort
      lines = []
      model = AgentModels.codex_model_for(effective)
      lines << %(model = "#{toml_inline_escape(model)}") if model && !model.to_s.empty?
      lines << %(model_reasoning_effort = "#{effort}")
      lines.join("\n")
    else
      %(model = "#{toml_inline_escape(effective.to_s)}")
    end
  end

  # Escape arbitrary text for a TOML multi-line basic string ("""..."""). Order matters:
  # normalize line endings, escape backslash FIRST (so introduced escapes are not
  # re-escaped), then EVERY double-quote (which alone prevents any triple-quote delimiter
  # collision), then C0 control chars other than tab/newline.
  def toml_ml_escape(str)
    s = str.to_s.gsub(/\r\n?/, "\n")
    s = s.gsub("\\") { "\\\\" }
    s = s.gsub('"') { '\\"' }
    s.gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f]/) { |c| format('\u%04X', c.ord) }
  end

  # Escape text for a single-line TOML basic string ("..."). Collapse any newline to a
  # space (single-line context), then the same backslash/quote/control escapes.
  def toml_inline_escape(str)
    s = str.to_s.gsub(/\s*\r?\n\s*/, " ").strip
    s = s.gsub("\\") { "\\\\" }
    s = s.gsub('"') { '\\"' }
    s.gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f]/) { |c| format('\u%04X', c.ord) }
  end

  def codex_dispatcher_path
    File.join(plastic_home, "scripts", "codex-hook")
  end

  # ~/.codex/hooks.json merge (intent 102). Guide-settled shape [guide Part 3]:
  # top-level {"hooks": {<Event>: [...]}}, identical to Claude's settings.json
  # hooks shape, so this mirrors merge_claude_hooks against a different file.
  # Both harnesses now match ownership by registry (intent 275), not a
  # substring: Codex by dispatcher filename equality, because its hooks are
  # arguments to one shared dispatcher command rather than per-hook launcher
  # files the way Claude's plastic-<name> launchers are.
  def merge_codex_hooks(hooks_json_path)
    data = read_json_safe(hooks_json_path) || {}
    hooks = data["hooks"] ||= {}
    removed = purge_stale_codex_hooks(hooks)
    report_removed_hook_entries(removed, "hooks.json")
    plastic = HookRegistry.codex_hooks_json(dispatcher_path: codex_dispatcher_path)
    plastic.each do |event, groups|
      hooks[event] ||= []
      Array(groups).each { |g| hooks[event] << g }
    end
    write_json_atomic(hooks_json_path, data)
  end

  # Returns [[event, command], ...] for every entry removed, mirroring
  # purge_stale_plastic_hooks. Ownership comes from HookRegistry (intent 275).
  def purge_stale_codex_hooks(hooks)
    removed = []

    hooks.each do |event, groups|
      next unless groups.is_a?(Array)

      hooks[event] = groups.map do |group|
        if group.is_a?(Hash) && group["hooks"].is_a?(Array)
          group["hooks"].reject! do |h|
            HookRegistry.codex_purge_command?(h["command"]) && (removed << [event, h["command"]])
          end
          group unless group["hooks"].empty?
        elsif group.is_a?(Hash) && group["command"]
          if HookRegistry.codex_purge_command?(group["command"])
            removed << [event, group["command"]]
            nil
          else
            group
          end
        else
          group
        end
      end.compact
    end

    removed
  end

  def install_hermes(config, force)
    FileUtils.mkdir_p(record_dir_for(config))

    installed = []
    skills_source = File.join(package_root, "skills")
    skill_exclude = advisor_enabled? ? [] : ["agent-advisor"]
    installed += install_skills_flat(skills_source, File.join(config[:dir], "skills"), exclude: skill_exclude) if File.directory?(skills_source)
    installed += install_agents(File.join(config[:dir], "agents"), models: agent_model_overrides, advisor_enabled: advisor_enabled?)

    # Uniform per-agent record (intent 210, D2): write VERSION alongside the manifest,
    # the same shape install_claude already writes.
    version_file = File.join(record_dir_for(config), "VERSION")
    File.write(version_file, "#{version}\n")
    installed << version_file

    write_manifest(installed, manifest_path_for("hermes", config))
    { agent: config[:name], success: true, files: installed.size }
  end

  # Copy each skills/<name>/ to <skills_root>/plastic-<name>/ (flat, namespaced by
  # directory name -- the only personal-skill namespacing Claude Code supports).
  # Any top-level underscore-prefixed markdown fragment (e.g. `_decision-tables.md`,
  # `_decision-tables.md`) is a shared non-skill fragment and relocates to ~/.plastic/
  # instead, so every skill can read it from one shared location. `exclude` skips
  # named top-level skill directories entirely (intent 185: the agent-advisor skill
  # when advisor.enabled is false).
  def install_skills_flat(skills_source, skills_root, exclude: [], transform: nil)
    installed = []
    FileUtils.mkdir_p(skills_root)

    Dir.children(skills_source).reject { |e| e.start_with?(".") || exclude.include?(e) }.each do |entry|
      src = File.join(skills_source, entry)
      if File.directory?(src)
        installed += copy_dir_recursive(src, File.join(skills_root, "plastic-#{entry}"),
                                        transform: transform, rel_prefix: entry)
      elsif entry.start_with?("_") && entry.end_with?(".md")
        # Spec D8: shared fragments land in the HARNESS-NEUTRAL plastic_home, shared
        # with any co-installed Claude. Never transformed, or a Codex install would
        # corrupt Claude's copy of the same file.
        FileUtils.mkdir_p(plastic_home)
        dest = File.join(plastic_home, entry)
        FileUtils.cp(src, dest)
        installed << dest
      end
    end

    installed
  end

  # Copy every repo agents/*.md into <agents_root> (flat, basename preserved), so
  # the role files install as ~/.claude/agents/<name>.md (and the codex/hermes
  # equivalents). Returns the installed destination paths so callers can append
  # them to `installed` before write_manifest (manifest + prune are then automatic).
  # No-op safe: returns [] when the package has no agents dir or it is empty.
  # advisor_enabled: false (advisor.enabled config key) skips every
  # AgentModels::CONSULTATION_AGENTS file entirely (both plastic-advisor and
  # plastic-faux-advisor), so a user who declined the advisor never gets either
  # agent installed.
  def install_agents(agents_root, models: {}, advisor_enabled: true)
    sources = Dir.glob(File.join(package_root, "agents", "*.md"))
    return [] if sources.empty?

    unless advisor_enabled
      sources = sources.reject { |src| AgentModels::CONSULTATION_AGENTS.include?(File.basename(src, ".md")) }
    end

    FileUtils.mkdir_p(agents_root)
    sources.map do |src|
      dest = File.join(agents_root, File.basename(src))
      basename = File.basename(src, ".md")
      override = models[basename]
      if override
        File.write(dest, rewrite_model_line(File.read(src), override))
      else
        FileUtils.cp(src, dest)
      end
      dest
    end
  end

  # Rewrite the single top-level `model:` line in a YAML frontmatter block.
  # Only the frontmatter (between the first two `---` fences) is touched.
  def rewrite_model_line(content, model)
    content.sub(/^model:[^\n]*$/, "model: #{model}")
  end

  # Resolve per-agent model overrides for this install: project config (when a
  # project dir is known) overlaid on global config, scoped to `harness`
  # ("claude" or "codex"). Defaults are NOT included, so unconfigured agents
  # keep their shipped frontmatter.
  #
  # Both advisor agents (plastic-advisor, plastic-faux-advisor) resolve through
  # this SAME generic map, like any other agent: a config author sets
  # agents.models.claude.plastic-advisor (or the legacy flat
  # agents.models.plastic-advisor, read as claude) to point either agent at a
  # different literal model. There is no separate advisor-specific model key;
  # which agent the advisor SKILL routes to by default is a routing decision
  # (advisor.claude.default), never a model-selection one.
  def agent_model_overrides(project_dir = nil, harness: "claude")
    global_config = load_config_yaml(File.join(plastic_home, "config.yml"))
    project_config =
      if project_dir
        load_config_yaml(File.join(project_dir, ".plastic_store", "config.yml"))
      else
        {}
      end
    AgentModels.override_map(project_config: project_config, global_config: global_config, harness: harness)
  end

  # advisor.enabled: project overlays global, missing or malformed counts as
  # enabled (fail-open). Harness-blind: false skips both advisor agents and the
  # agent-advisor skill on every installed harness.
  def advisor_enabled?(project_dir = nil)
    global_config = load_config_yaml(File.join(plastic_home, "config.yml"))
    project_config = project_dir ? load_config_yaml(File.join(project_dir, ".plastic_store", "config.yml")) : {}
    value = project_config.dig("advisor", "enabled")
    value = global_config.dig("advisor", "enabled") if value.nil?
    value != false
  end

  # Agent-name shorthands for the --advisor flag: the two shipped choices,
  # named for the role (real advisor vs. the cheaper imitation), never a model
  # name.
  ADVISOR_SHORTHANDS = { "real" => "plastic-advisor", "faux" => "plastic-faux-advisor" }.freeze

  # Write advisor.enabled / advisor.claude.default into the global config.yml
  # from install-time flags. Absent flags change nothing: advisor.enabled
  # defaults to enabled when missing, and advisor.claude.default is left unset
  # (the skill's own fallback chain applies) when missing.
  #   --no-advisor      -> advisor.enabled: false
  #   --advisor VALUE   -> advisor.claude.default: VALUE (an agent name, or the
  #                        shorthand "real"/"faux")
  def apply_config_flags(argv)
    no_advisor = argv.include?("--no-advisor")
    advisor_idx = argv.index("--advisor")
    advisor_value = advisor_idx && argv[advisor_idx + 1]
    return unless no_advisor || advisor_value

    config_path = File.join(plastic_home, "config.yml")
    config = load_config_yaml(config_path)

    if no_advisor
      config["advisor"] ||= {}
      config["advisor"]["enabled"] = false
    end
    if advisor_value
      agent_name = ADVISOR_SHORTHANDS[advisor_value] || advisor_value
      config["advisor"] ||= {}
      config["advisor"]["claude"] ||= {}
      config["advisor"]["claude"]["default"] = agent_name
    end

    FileUtils.mkdir_p(plastic_home)
    File.write(config_path, YAML.dump(config))
  end

  def load_config_yaml(path)
    return {} unless File.exist?(path)
    YAML.safe_load(File.read(path)) || {}
  rescue StandardError
    {}
  end

  # --- Legacy plugin migration ---

  # Earlier versions registered Plastic as a local marketplace plugin
  # (plastic@plastic) for skill discovery. The current model uses flat,
  # hyphen-namespaced personal skills, so any prior plugin layout is removed here
  # to stop the two coexisting. Returns a list of what was migrated.
  def migrate_legacy_plugin(claude_dir)
    removed = []

    legacy_dirs = [
      File.join(claude_dir, "plugins", "marketplaces", "plastic"),
      File.join(claude_dir, "plugins", "cache", "plastic"),
      File.join(claude_dir, "skills", "plastic"), # old nested skills layout
    ]
    legacy_dirs.each do |d|
      if File.directory?(d)
        FileUtils.rm_rf(d)
        removed << d
      end
    end

    # settings.json: drop enabledPlugins + extraKnownMarketplaces entries
    settings_path = File.join(claude_dir, "settings.json")
    settings = read_json_safe(settings_path)
    if settings
      changed = false
      if settings.dig("enabledPlugins", "plastic@plastic")
        settings["enabledPlugins"].delete("plastic@plastic")
        settings.delete("enabledPlugins") if settings["enabledPlugins"].empty?
        changed = true
      end
      if settings.dig("extraKnownMarketplaces", "plastic")
        settings["extraKnownMarketplaces"].delete("plastic")
        settings.delete("extraKnownMarketplaces") if settings["extraKnownMarketplaces"].empty?
        changed = true
      end
      if changed
        write_json_atomic(settings_path, settings)
        removed << "settings.json: plastic@plastic plugin registration"
      end
    end

    # plugins/known_marketplaces.json: drop the plastic entry
    known_path = File.join(claude_dir, "plugins", "known_marketplaces.json")
    known = read_json_safe(known_path)
    if known.is_a?(Hash) && known.key?("plastic")
      known.delete("plastic")
      write_json_atomic(known_path, known)
      removed << "known_marketplaces.json: plastic"
    end

    unless removed.empty?
      puts "  \u{1f9f9} Migrated legacy plugin install:"
      removed.each { |r| puts "     - #{tilde(r)}" }
    end

    removed
  end

  def tilde(path)
    path.sub(Dir.home, "~")
  end

  def report_removed_hook_entries(removed, file_label, qualifier: "stale Plastic")
    return if removed.nil? || removed.empty?

    puts "  \u{1f9f9} Removed #{removed.size} #{qualifier} hook entr#{removed.size == 1 ? "y" : "ies"} from #{file_label}:"
    removed.each { |event, command| puts "     - #{event}: #{tilde(command.to_s)}" }
  end

  # The statusline swap-back on uninstall is not an [event, command] pair: it is a
  # value restored, not an entry deleted. It gets its own line rather than being
  # forced into the entry list (intent 278).
  def report_removed_statusline(restored_command, file_label = "settings.json")
    puts "  \u{1f9f9} Removed Plastic's statusLine from #{file_label}."
    return if restored_command.nil? || restored_command.to_s.empty?

    puts "     - restored your original statusLine: #{tilde(restored_command.to_s)}"
  end

  # The other half of intent 275: a hook the purge KEPT because the registry does not
  # know it, but whose name carries Plastic's prefix. Silence here is what let the
  # 1.11.0 update delete the owner's plastic-writing-style hook unnoticed; now the
  # update says the prefix is reserved and the hook stays.
  def report_reserved_prefix_hooks(hooks)
    kept = hooks.flat_map do |_event, groups|
      next [] unless groups.is_a?(Array)

      groups.flat_map { |g| g.is_a?(Hash) ? Array(g["hooks"]).map { |h| h["command"] } + [g["command"]] : [] }
    end.compact.select { |cmd| cmd.to_s.include?("plastic-") }.uniq

    return if kept.empty?

    puts "  \u{2139}\u{fe0f}  Kept #{kept.size} hook(s) Plastic does not own, named with the reserved plastic- prefix:"
    kept.each { |cmd| puts "     - #{tilde(cmd.to_s)}" }
    puts "     The plastic- prefix is reserved for Plastic's own hooks. Rename yours (for"
    puts "     example ~/.claude/hooks/writing-style) so a future update never mistakes it."
  end

  # --- settings.json merge (read-modify-write, never clobber) ---

  def merge_claude_hooks(settings_path, choice: :plastic)
    settings = read_json_safe(settings_path) || {}
    return if settings.nil?

    hooks = settings["hooks"] ||= {}
    hook_dir = File.join(Dir.home, ".claude", "hooks")

    removed = purge_stale_plastic_hooks(hooks)
    report_removed_hook_entries(removed, "settings.json")
    report_reserved_prefix_hooks(hooks)

    # Single source of truth (intent 108, D7): registrations live in
    # HookRegistry; this merge only translates them into settings.json.
    plastic_hooks = HookRegistry.claude_settings_hooks(hook_dir: hook_dir)

    plastic_hooks.each do |event, group|
      hooks[event] ||= []

      # An event may map to a LIST of plastic groups (none does since the edit-path
      # gates left in 2.0, intent 302; the shape stays). The purge pass above already removed all
      # prior plastic groups, so appending each desired group fresh is idempotent
      # across re-runs and never collapses two matchers into one group.
      groups = group.is_a?(Array) ? group : [group]
      groups.each do |g|
        existing = hooks[event].find do |h|
          h.is_a?(Hash) && h["matcher"] == g["matcher"] &&
            h["hooks"].is_a?(Array) && h["hooks"].any? { |x| HookRegistry.claude_purge_command?(x["command"]) }
        end

        if existing
          existing["hooks"] = g["hooks"]
        else
          hooks[event] << g
        end
      end
    end

    existing_status = settings["statusLine"]
    if existing_status && !HookRegistry.claude_purge_command?(existing_status["command"])
      cache_dir = File.join(plastic_home, ".cache")
      FileUtils.mkdir_p(cache_dir)
      File.write(File.join(cache_dir, "original-statusline.json"), JSON.pretty_generate(existing_status))
    end

    settings["statusLine"] = { "type" => "command", "command" => "#{hook_dir}/plastic-statusline" } if choice == :plastic

    # No plugin/marketplace registration: skills are flat personal skills
    # (plastic-<name>/) discovered directly from ~/.claude/skills.

    write_json_atomic(settings_path, settings)
  end

  # Returns [[event, command], ...] for every entry removed, so merge_claude_hooks
  # can report it. Ownership comes from HookRegistry (intent 275), never a substring.
  def purge_stale_plastic_hooks(hooks)
    removed = []
    hooks.delete("statusLine")

    hooks.each do |event, groups|
      next unless groups.is_a?(Array)

      hooks[event] = groups.map do |group|
        if group.is_a?(Hash) && group["hooks"].is_a?(Array)
          group["hooks"].reject! do |h|
            HookRegistry.claude_purge_command?(h["command"]) && (removed << [event, h["command"]])
          end
          group unless group["hooks"].empty?
        elsif group.is_a?(Hash) && group["command"]
          if HookRegistry.claude_purge_command?(group["command"])
            removed << [event, group["command"]]
            nil
          else
            group
          end
        else
          group
        end
      end.compact
    end

    removed
  end

  # --- Codex AGENTS.md marked-section injection (22a/Beads pattern) ---
  # New primitive: markdown marked-section merge, the analog of merge_claude_hooks'
  # JSON read-modify-write for a partial-ownership text file. Three states
  # (create/append/replace), a body freshness hash in the BEGIN marker, atomic
  # writes, and the 22a safety rule: never write when the existing section can't
  # be parsed (a BEGIN marker with no matching END).

  # Atomic text writer, mirrors write_json_atomic.
  def write_text_atomic(path, content)
    tmp = "#{path}.plastic-tmp.#{Process.pid}"
    File.write(tmp, content)
    File.rename(tmp, path)
  rescue => e
    File.delete(tmp) if tmp && File.exist?(tmp)
    raise e
  end

  # A managed instruction file may be a symlink into a dotfiles repo. write_text_atomic
  # renames a temp file over its argument, which would replace the link with a regular
  # file and silently detach it, so every read and write resolves the link first and the
  # change lands on its target (intent 312).
  def resolve_managed_path(path)
    File.symlink?(path) ? File.realpath(path) : path
  rescue Errno::ENOENT
    path
  end

  def marked_section(body: CODEX_AGENTS_MD_BODY, begin_prefix: CODEX_SECTION_BEGIN_PREFIX,
                     end_marker: CODEX_SECTION_END)
    hash = Digest::SHA256.hexdigest(body)[0, 12]
    "#{begin_prefix} hash:#{hash} -->\n#{body.strip}\n#{end_marker}\n"
  end

  # Returns :created / :appended / :replaced / :refused. Never raises on a normal user file.
  def inject_marked_section(path, body: CODEX_AGENTS_MD_BODY,
                            begin_prefix: CODEX_SECTION_BEGIN_PREFIX,
                            end_marker: CODEX_SECTION_END, section_re: CODEX_SECTION_RE)
    section = marked_section(body: body, begin_prefix: begin_prefix, end_marker: end_marker)
    path = resolve_managed_path(path)

    unless File.exist?(path)
      FileUtils.mkdir_p(File.dirname(path))
      write_text_atomic(path, section)
      return :created
    end

    content = File.read(path)
    has_begin = content.include?(begin_prefix)
    has_end = content.include?(end_marker)

    # 22a safety rule: never write if the existing section cannot be parsed.
    return :refused if has_begin && !has_end

    if has_begin
      write_text_atomic(path, content.sub(section_re, section))
      :replaced
    else
      base = content.end_with?("\n") ? content : content + "\n"
      write_text_atomic(path, base + "\n" + section)
      :appended
    end
  end

  # --- The two blocks Plastic ships, each with its own marker pair ---

  def codex_section(body: CODEX_AGENTS_MD_BODY)
    marked_section(body: body)
  end

  def inject_codex_agents_md(path, body: CODEX_AGENTS_MD_BODY)
    inject_marked_section(path, body: body)
  end

  # The compact-instructions block for ~/.claude/CLAUDE.md (intent 312).
  def claude_compact_section(body: CompactInstructions::BODY)
    marked_section(body: body, begin_prefix: CLAUDE_SECTION_BEGIN_PREFIX,
                   end_marker: CLAUDE_SECTION_END)
  end

  def inject_claude_compact_md(path, body: CompactInstructions::BODY)
    inject_marked_section(path, body: body, begin_prefix: CLAUDE_SECTION_BEGIN_PREFIX,
                          end_marker: CLAUDE_SECTION_END, section_re: CLAUDE_SECTION_RE)
  end

  # Remove exactly Plastic's managed section from a user-owned AGENTS.md. Preserve all other
  # content. Delete the file only if Plastic created it and nothing else remains. Returns the
  # path when it acted, nil on no-op. Mirrors remove_claude_hooks: dedicated surgical strip,
  # never the manifest whole-file-delete path.
  def strip_marked_section(path, begin_prefix: CODEX_SECTION_BEGIN_PREFIX,
                           section_re: CODEX_SECTION_RE)
    path = resolve_managed_path(path)
    return nil unless File.exist?(path)
    content = File.read(path)
    return nil unless content.include?(begin_prefix)

    # Remove the section plus the single separator newline the append introduced, so a
    # standard user file round-trips byte-identical.
    stripped = content.sub(/\n?#{section_re}/, "")

    if stripped.strip.empty?
      File.delete(path)                 # Plastic-created file: nothing else left
    else
      stripped = stripped.rstrip + "\n" # normalize trailing whitespace we may have left
      write_text_atomic(path, stripped)
    end
    path
  end

  def strip_codex_section(path)
    strip_marked_section(path)
  end

  def strip_claude_compact_section(path)
    strip_marked_section(path, begin_prefix: CLAUDE_SECTION_BEGIN_PREFIX,
                         section_re: CLAUDE_SECTION_RE)
  end

  # --- Uninstall ---

  def handle_uninstall(uninstall_agents)
    uninstall_agents.each do |key|
      config = agent_config(key)
      next unless config

      result = uninstall_agent(key, config)
      unless result[:success]
        puts "  \u{26a0}\u{fe0f}  #{config[:name]}: #{result[:reason]}"
        next
      end

      puts "  \u{2705} #{config[:name]}: uninstalled (#{result[:files]} files removed)"
      result[:removed].each { |r| puts "     removed: #{tilde(r)}" }
    end

    # What was deliberately left behind
    puts "\n  Left in place (not removed):"
    puts "     - #{tilde(plastic_home)} (your intent store, history, and projects)"
    puts "     - any non-Plastic entries in settings.json"

    puts "\n  Verify removal:"
    puts "     ls ~/.claude/skills | grep '^plastic-'      # → no output"
    puts "     ls ~/.claude/hooks | grep '^plastic-'       # → no output"
    puts "     grep -c plastic ~/.claude/settings.json     # → only hook refs gone"
    puts "     grep 'PLASTIC COMPACT' ~/.claude/CLAUDE.md  # → no output"
    puts "\n  To also delete your intent store: rm -rf #{tilde(plastic_home)}\n\n"
  end

  def uninstall_agent(key, config)
    unless File.directory?(config[:dir])
      return { success: false, reason: "#{config[:dir]} not found" }
    end

    removed = []
    manifest_path = manifest_path_for(key, config)

    if File.exist?(manifest_path)
      manifest = JSON.parse(File.read(manifest_path)) rescue {}
      (manifest["files"] || {}).each_key do |f|
        if File.exist?(f)
          File.delete(f)
          removed << f
        end
      end
      File.delete(manifest_path)
      removed << manifest_path
    end

    # Remove flat plastic-<name>/ skill dirs (now-empty after manifest deletion,
    # plus any the manifest missed) and the plastic state dir.
    skills_root = File.join(config[:dir], "skills")
    if File.directory?(skills_root)
      Dir.children(skills_root).select { |e| e.start_with?("plastic-") }.each do |d|
        full = File.join(skills_root, d)
        FileUtils.rm_rf(full)
        removed << full
      end
    end

    [File.join(config[:dir], "plastic")].each do |d|
      if File.directory?(d)
        FileUtils.rm_rf(d)
        removed << d
      end
    end

    # Claude Code: clean hooks/statusline and any legacy plugin registration
    if key == "claude"
      settings_path = File.join(config[:dir], "settings.json")
      remove_claude_hooks(settings_path) if File.exist?(settings_path)
      removed.concat(migrate_legacy_plugin(config[:dir]))

      # The compact-instructions block in the user-owned CLAUDE.md (intent 312): a
      # surgical strip, never the manifest whole-file-delete path above.
      stripped = strip_claude_compact_section(File.join(config[:dir], "CLAUDE.md"))
      removed << stripped if stripped
    end

    # Codex: surgically strip Plastic's marked section from the user-owned AGENTS.md
    # (dedicated pair, never the manifest whole-file-delete path above), plus the
    # Plastic entries from hooks.json (intent 102).
    if key == "codex"
      agents_md = File.join(config[:home_dir], "AGENTS.md")
      stripped = strip_codex_section(agents_md)
      removed << stripped if stripped

      hooks_json = File.join(config[:home_dir], "hooks.json")
      hooks_removed = remove_codex_hooks(hooks_json)
      removed << hooks_removed if hooks_removed
    end

    { success: true, files: removed.size, removed: removed }
  end

  def remove_claude_hooks(settings_path)
    settings = read_json_safe(settings_path)
    return unless settings && settings["hooks"]

    removed = []

    settings["hooks"].each do |event, groups|
      next unless groups.is_a?(Array)

      settings["hooks"][event] = groups.map do |group|
        if group.is_a?(Hash) && group["hooks"].is_a?(Array)
          group["hooks"].reject! do |h|
            HookRegistry.claude_purge_command?(h["command"]) && (removed << [event, h["command"]])
          end
          group unless group["hooks"].empty?
        elsif group.is_a?(Hash) && group["command"]
          if HookRegistry.claude_purge_command?(group["command"])
            removed << [event, group["command"]]
            nil
          else
            group
          end
        else
          group
        end
      end.compact
    end

    settings["hooks"].delete_if { |_, v| v.is_a?(Array) && v.empty? }
    settings.delete("hooks") if settings["hooks"]&.empty?

    statusline_removed = false
    restored_statusline = nil
    if HookRegistry.claude_purge_command?(settings.dig("statusLine", "command"))
      settings.delete("statusLine")
      statusline_removed = true
      original_path = File.join(plastic_home, ".cache", "original-statusline.json")
      if File.exist?(original_path)
        original = JSON.parse(File.read(original_path)) rescue nil
        if original.is_a?(Hash)
          settings["statusLine"] = original
          restored_statusline = original["command"]
        end
      end
    end

    # Remove from enabledPlugins
    if settings["enabledPlugins"]
      settings["enabledPlugins"].delete("plastic@plastic")
      settings.delete("enabledPlugins") if settings["enabledPlugins"].empty?
    end

    result = write_json_atomic(settings_path, settings)
    report_removed_hook_entries(removed, "settings.json", qualifier: "Plastic")
    report_removed_statusline(restored_statusline) if statusline_removed
    result
  end

  # Remove exactly Plastic's entries from ~/.codex/hooks.json (intent 102), mirrors
  # remove_claude_hooks against the Codex file/purge predicate. Returns the path
  # when it acted (rewritten or deleted), nil on no-op, mirroring strip_codex_section's
  # convention so the caller only records an actual change.
  def remove_codex_hooks(hooks_json_path)
    data = read_json_safe(hooks_json_path)
    return nil unless data && data["hooks"]

    before = JSON.generate(data)
    removed = []

    data["hooks"].each do |event, groups|
      next unless groups.is_a?(Array)

      data["hooks"][event] = groups.map do |g|
        next g unless g.is_a?(Hash) && Array(g["hooks"]).is_a?(Array)

        g["hooks"] = Array(g["hooks"]).reject do |h|
          HookRegistry.codex_purge_command?(h["command"]) && (removed << [event, h["command"]])
        end
        g["hooks"].empty? ? nil : g
      end.compact
    end
    data["hooks"].delete_if { |_, v| v.is_a?(Array) && v.empty? }

    return nil if JSON.generate(data) == before # nothing to change: true no-op

    if data["hooks"].empty? && data.keys == ["hooks"]
      File.delete(hooks_json_path) # Plastic-created and now empty: remove
    else
      write_json_atomic(hooks_json_path, data)
    end
    report_removed_hook_entries(removed, "hooks.json", qualifier: "Plastic")
    hooks_json_path
  end

  # --- Utilities ---

  def agent_config(key)
    agents.find { |a| a[:key] == key }
  end

  def copy_dir_recursive(src, dest, transform: nil, rel_prefix: "")
    files = []
    FileUtils.mkdir_p(dest)
    Dir.entries(src).reject { |e| e.start_with?(".") }.each do |entry|
      src_path = File.join(src, entry)
      dest_path = File.join(dest, entry)
      rel = rel_prefix.empty? ? entry : File.join(rel_prefix, entry)
      if File.directory?(src_path)
        files += copy_dir_recursive(src_path, dest_path, transform: transform, rel_prefix: rel)
      elsif File.file?(src_path)
        if transform && File.extname(entry) == ".md"
          File.write(dest_path, transform.call(File.read(src_path), rel))
          File.chmod(File.stat(src_path).mode & 0o7777, dest_path)
        else
          FileUtils.cp(src_path, dest_path)
        end
        files << dest_path
      end
    end
    files
  end

  def read_json_safe(path)
    return nil unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError
    # Try JSONC stripping (remove // comments and trailing commas)
    content = File.read(path).gsub(%r{//[^\n]*}, "").gsub(/,(\s*[}\]])/, '\1')
    JSON.parse(content)
  rescue
    nil
  end

  def write_json_atomic(path, data)
    content = JSON.pretty_generate(data) + "\n"
    tmp = "#{path}.plastic-tmp.#{Process.pid}"
    File.write(tmp, content)
    File.rename(tmp, path)
  rescue => e
    File.delete(tmp) if tmp && File.exist?(tmp)
    raise e
  end

  def write_manifest(files, manifest_path)
    entries = {}
    files.each do |f|
      entries[f] = Digest::SHA256.file(f).hexdigest if File.exist?(f)
    end

    data = { "version" => "1", "created" => Time.now.utc.iso8601, "files" => entries }
    File.write(manifest_path, JSON.pretty_generate(data) + "\n")
  end

  def write_if_missing(path, content)
    File.write(path, content) unless File.exist?(path)
  end
end
