# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"
require "digest"
require "time"

# Shared installer machinery, instantiable with injected package root / store / agent
# map so the verb scripts (install/update/uninstall/versions) and their tests can run
# hermetically (no eval, no global-constant rewriting). Mirrors the DI recipe proven in
# doctor.rb / install.rb (intents 30a, 30a1). Library only — no CLI, no $PROGRAM_NAME guard.
class InstallerCore
  DEFAULT_PLASTIC_HOME = File.join(Dir.home, ".plastic")

  DEFAULT_AGENTS = [
    { key: "claude", name: "Claude Code", dir: File.join(Dir.home, ".claude"), flag: "--claude" },
    { key: "codex", name: "Codex CLI", dir: File.join(Dir.home, ".agents"), flag: "--codex" },
    { key: "hermes", name: "Hermes", dir: File.join(Dir.home, ".hermes"), flag: "--hermes" },
  ].freeze

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

  # --- Semver (§11) — parse/compare, shared by update + versions ---

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

  # --- versions.json ledger (append-only JSONL — one object per line) ---

  def ledger_path
    File.join(plastic_home, "versions.json")
  end

  # Append a single immutable entry. Opens in append mode; never rewrites prior lines.
  # action ∈ { install, reinstall, update, downgrade }.
  def ledger_append(entry_version, action)
    FileUtils.mkdir_p(plastic_home)
    line = JSON.generate("version" => entry_version, "action" => action, "at" => Time.now.utc.iso8601)
    File.open(ledger_path, "a") { |f| f.puts(line) }
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

  def channel_from(argv, default: "latest")
    return "alpha" if argv.include?("--alpha")
    return "beta" if argv.include?("--beta")
    return "latest" if argv.include?("--latest")
    default
  end

  def prompt_agents(input: $stdin)
    return ["claude"] unless input.tty?

    puts "Which agents should Plastic register for?\n\n"
    agents.each_with_index { |a, i| puts "  #{i + 1}. #{a[:name]} (#{a[:dir]})" }
    puts "  #{agents.size + 1}. All"
    puts

    print "Select (comma-separated numbers, or Enter for Claude Code): "
    answer = input.gets&.strip || ""

    return ["claude"] if answer.empty?

    nums = answer.split(",").map { |n| n.strip.to_i }
    return agents.map { |a| a[:key] } if nums.include?(agents.size + 1)

    nums.select { |n| n >= 1 && n <= agents.size }.map { |n| agents[n - 1][:key] }
  end

  # --- Distribution phase ---

  def distribute(mode)
    puts "  \u{1f4e6} #{mode == :update ? "Updating" : "Installing"} core files to #{plastic_home}"

    FileUtils.mkdir_p(plastic_home)
    FileUtils.mkdir_p(File.join(plastic_home, "scripts", "lib"))
    FileUtils.mkdir_p(File.join(plastic_home, "templates"))

    core_files.each do |src, dest|
      src_path = File.join(package_root, src)
      dest_path = File.join(plastic_home, dest)
      next unless File.exist?(src_path)

      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(src_path, dest_path)
    end

    File.write(File.join(plastic_home, "VERSION"), "#{version}\n")

    Dir.glob(File.join(plastic_home, "scripts", "*")).each { |f| FileUtils.chmod(0o755, f) if File.file?(f) }

    global_files = core_files.values.map { |d| File.join(plastic_home, d) }
    global_files << File.join(plastic_home, "VERSION")
    global_files = global_files.select { |p| File.exist?(p) }
    write_manifest(global_files, File.join(plastic_home, "manifest.json"))

    puts "  \u{2705} Core files synced (v#{version})"
  end

  # Files copied into ~/.plastic on install/update. Every verb script + the shared lib
  # must be here so the installed ~/.plastic/scripts copy is self-complete (sync-guarded
  # by install_sync_test).
  def core_files
    {
      "PLASTIC.md" => "PLASTIC.md",
      "deprecations.yml" => "deprecations.yml",
      "scripts/folgezettel-id" => "scripts/folgezettel-id",
      "scripts/read-config" => "scripts/read-config",
      "scripts/select-update-target" => "scripts/select-update-target",
      "scripts/hook-session-start" => "scripts/hook-session-start",
      "scripts/hook-continue" => "scripts/hook-continue",
      "scripts/hook-future-intent-check" => "scripts/hook-future-intent-check",
      "scripts/hook-gate-check" => "scripts/hook-gate-check",
      "scripts/hook-savepoint-pre" => "scripts/hook-savepoint-pre",
      "scripts/hook-qmd-search" => "scripts/hook-qmd-search",
      "scripts/lib/qmd_hook.rb" => "scripts/lib/qmd_hook.rb",
      "scripts/lib/power_tools.rb" => "scripts/lib/power_tools.rb",
      "scripts/hook-code-gate" => "scripts/hook-code-gate",
      "scripts/hook-bash-gate" => "scripts/hook-bash-gate",
      "scripts/hook-retrieval-gate" => "scripts/hook-retrieval-gate",
      "scripts/lib/retrieval_gate.rb" => "scripts/lib/retrieval_gate.rb",
      "scripts/hook-auto-arm" => "scripts/hook-auto-arm",
      "scripts/lib/bridge.rb" => "scripts/lib/bridge.rb",
      "scripts/lib/worktree.rb" => "scripts/lib/worktree.rb",
      "scripts/lib/boot_banner.rb" => "scripts/lib/boot_banner.rb",
      "scripts/lib/qmd_sync.rb" => "scripts/lib/qmd_sync.rb",
      "scripts/qmd-sync" => "scripts/qmd-sync",
      "scripts/lib/intent_validator.rb" => "scripts/lib/intent_validator.rb",
      "scripts/lib/graph_rebuild.rb" => "scripts/lib/graph_rebuild.rb",
      "scripts/lib/frontmatter_writer.rb" => "scripts/lib/frontmatter_writer.rb",
      "scripts/lib/links_projection.rb" => "scripts/lib/links_projection.rb",
      "scripts/lib/links_section.rb" => "scripts/lib/links_section.rb",
      "scripts/project-links" => "scripts/project-links",
      "scripts/rebuild-graph" => "scripts/rebuild-graph",
      "scripts/validate-intent" => "scripts/validate-intent",
      "scripts/new-intent" => "scripts/new-intent",
      "scripts/hook-create-gate" => "scripts/hook-create-gate",
      "templates/intent.md" => "templates/intent.md",
      "templates/spec.md" => "templates/spec.md",
      "templates/plan.md" => "templates/plan.md",
      "templates/checklist.md" => "templates/checklist.md",
      "templates/outcome.md" => "templates/outcome.md",
      "scripts/spawn-preamble" => "scripts/spawn-preamble",
      "scripts/lib/store_provisioning.rb" => "scripts/lib/store_provisioning.rb",
      "scripts/provision-project-store" => "scripts/provision-project-store",
      "scripts/lib/installer_core.rb" => "scripts/lib/installer_core.rb",
      "scripts/install.rb" => "scripts/install.rb",
      "scripts/update.rb" => "scripts/update.rb",
      "scripts/uninstall.rb" => "scripts/uninstall.rb",
      "scripts/versions.rb" => "scripts/versions.rb",
      "scripts/doctor.rb" => "scripts/doctor.rb",
      "scripts/dashboard.rb" => "scripts/dashboard.rb",
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
      # Plastic \u{2014} Agent Instructions

      Read `PLASTIC.md` in this directory. It contains all Plastic conventions.
      Follow it exactly. Never modify it \u{2014} it is overwritten on plugin updates.

      This file (`AGENTS.md`) is where project-specific rules live.

      ---
    MD

    puts "  \u{2705} Store bootstrapped"
  end

  # --- Agent adapters ---

  def manifest_path_for(key, config)
    case key
    when "claude" then File.join(config[:dir], "plastic", "manifest.json")
    else File.join(config[:dir], "plastic-manifest.json")
    end
  end

  def manifest_files(manifest_path)
    return [] unless File.exist?(manifest_path)
    data = JSON.parse(File.read(manifest_path)) rescue {}
    (data["files"] || {}).keys
  end

  def install_for_agent(key, force)
    config = agent_config(key)
    return { agent: config[:name], success: false, reason: "Unknown agent" } unless config

    unless File.directory?(config[:dir])
      return { agent: config[:name], success: false, reason: "#{config[:dir]} not found \u{2014} #{config[:name]} not installed?" }
    end

    # Capture the prior manifest so we can prune files that no longer ship
    # (renamed/removed skills) after a re-copy. This gives leftover-free updates.
    old_files = manifest_files(manifest_path_for(key, config))

    result = case key
             when "claude" then install_claude(config, force)
             when "codex" then install_codex(config, force)
             when "hermes" then install_hermes(config, force)
             end

    new_files = manifest_files(manifest_path_for(key, config))
    pruned = prune_removed_files(old_files - new_files)
    result[:pruned] = pruned if pruned.positive?
    result
  end

  # Delete tracked files present in the old manifest but absent from the new one,
  # then remove any now-empty skill directories they lived in.
  def prune_removed_files(stale_files)
    removed = 0
    dirs = []
    stale_files.each do |f|
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

  def install_claude(config, force)
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

    # Copy skills as flat, hyphen-namespaced personal skills (plastic-<name>/)
    skills_source = File.join(package_root, "skills")
    installed += install_skills_flat(skills_source, skills_root) if File.directory?(skills_source)

    # Copy agent role files into <dir>/agents (manifest-tracked, pruned on update)
    installed += install_agents(File.join(config[:dir], "agents"))

    # Write VERSION
    version_file = File.join(plastic_dir, "VERSION")
    File.write(version_file, "#{version}\n")
    installed << version_file

    # Remove any prior plugin/marketplace install so the layouts don't coexist
    migrate_legacy_plugin(config[:dir])

    # Merge hooks + statusline into settings.json (no plugin registration)
    settings_path = File.join(config[:dir], "settings.json")
    merge_claude_hooks(settings_path)

    # Write manifest
    manifest_path = File.join(plastic_dir, "manifest.json")
    write_manifest(installed, manifest_path)

    { agent: config[:name], success: true, files: installed.size }
  end

  def install_codex(config, force)
    installed = []
    skills_source = File.join(package_root, "skills")
    installed += install_skills_flat(skills_source, File.join(config[:dir], "skills")) if File.directory?(skills_source)
    installed += install_agents(File.join(config[:dir], "agents"))

    write_manifest(installed, File.join(config[:dir], "plastic-manifest.json"))
    { agent: config[:name], success: true, files: installed.size }
  end

  def install_hermes(config, force)
    installed = []
    skills_source = File.join(package_root, "skills")
    installed += install_skills_flat(skills_source, File.join(config[:dir], "skills")) if File.directory?(skills_source)
    installed += install_agents(File.join(config[:dir], "agents"))

    write_manifest(installed, File.join(config[:dir], "plastic-manifest.json"))
    { agent: config[:name], success: true, files: installed.size }
  end

  # Copy each skills/<name>/ to <skills_root>/plastic-<name>/ (flat, namespaced by
  # directory name — the only personal-skill namespacing Claude Code supports).
  # The non-skill `_active-intent-gate.md` is relocated to ~/.plastic/ instead.
  def install_skills_flat(skills_source, skills_root)
    installed = []
    FileUtils.mkdir_p(skills_root)

    Dir.children(skills_source).reject { |e| e.start_with?(".") }.each do |entry|
      src = File.join(skills_source, entry)
      if File.directory?(src)
        installed += copy_dir_recursive(src, File.join(skills_root, "plastic-#{entry}"))
      elsif entry == "_active-intent-gate.md"
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
  def install_agents(agents_root)
    sources = Dir.glob(File.join(package_root, "agents", "*.md"))
    return [] if sources.empty?

    FileUtils.mkdir_p(agents_root)
    sources.map do |src|
      dest = File.join(agents_root, File.basename(src))
      FileUtils.cp(src, dest)
      dest
    end
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

  # --- settings.json merge (read-modify-write, never clobber) ---

  def merge_claude_hooks(settings_path)
    settings = read_json_safe(settings_path) || {}
    return if settings.nil?

    hooks = settings["hooks"] ||= {}
    hook_dir = File.join(Dir.home, ".claude", "hooks")

    purge_stale_plastic_hooks(hooks)

    plastic_hooks = {
      "SessionStart" => {
        "matcher" => "",
        "hooks" => [
          { "type" => "command", "command" => "#{hook_dir}/plastic-session-start", "statusMessage" => "Loading Plastic context..." },
          { "type" => "command", "command" => "#{hook_dir}/plastic-check-update", "statusMessage" => "" },
        ],
      },
      "PreCompact" => {
        "matcher" => "",
        "hooks" => [
          { "type" => "command", "command" => "#{hook_dir}/plastic-savepoint", "statusMessage" => "Saving Plastic intent state..." },
        ],
      },
      # PreToolUse carries TWO plastic groups with distinct matchers: the
      # code-gate (Write|Edit|NotebookEdit) and the create-gate (Write only, intent
      # 60b). A single group cannot carry two matchers, so this event maps to a
      # LIST of groups; the merge loop appends each (idempotent because the purge
      # pass removes all prior plastic groups first).
      "PreToolUse" => [
        {
          "matcher" => "Write|Edit|NotebookEdit",
          "hooks" => [
            { "type" => "command", "command" => "#{hook_dir}/plastic-code-gate", "statusMessage" => "Checking lifecycle gate..." },
          ],
        },
        {
          "matcher" => "Write",
          "hooks" => [
            { "type" => "command", "command" => "#{hook_dir}/plastic-create-gate", "statusMessage" => "Checking create gate..." },
          ],
        },
        # Retrieval gate (intent 84, Lever 2): redirects store-markdown reads to
        # QMD and code reads to Serena when those tools are present. Binds the
        # main agent AND subagents (PreToolUse applies to subagent tool calls).
        {
          "matcher" => "Bash|Read|Grep|Glob",
          "hooks" => [
            { "type" => "command", "command" => "#{hook_dir}/plastic-retrieval-gate", "statusMessage" => "Checking retrieval gate..." },
          ],
        },
      ],
      "PostToolUse" => {
        "matcher" => "Write|Edit",
        "hooks" => [
          { "type" => "command", "command" => "#{hook_dir}/plastic-gate-check", "statusMessage" => "Checking lifecycle gates..." },
        ],
      },
      "UserPromptSubmit" => {
        "matcher" => "",
        "hooks" => [
          { "type" => "command", "command" => "#{hook_dir}/plastic-continue", "statusMessage" => "Checking for continue..." },
          { "type" => "command", "command" => "#{hook_dir}/plastic-future-intent-check", "statusMessage" => "Checking future intents..." },
          { "type" => "command", "command" => "#{hook_dir}/plastic-auto-arm", "statusMessage" => "Checking auto mode..." },
          { "type" => "command", "command" => "#{hook_dir}/plastic-qmd-search", "statusMessage" => "Searching QMD..." },
        ],
      },
    }

    plastic_hooks.each do |event, group|
      hooks[event] ||= []

      # An event may map to a LIST of plastic groups (PreToolUse carries the
      # code-gate AND the create-gate). The purge pass above already removed all
      # prior plastic groups, so appending each desired group fresh is idempotent
      # across re-runs and never collapses two matchers into one group.
      groups = group.is_a?(Array) ? group : [group]
      groups.each do |g|
        existing = hooks[event].find do |h|
          h.is_a?(Hash) && h["matcher"] == g["matcher"] &&
            h["hooks"].is_a?(Array) && h["hooks"].any? { |x| x["command"].to_s.include?("plastic-") }
        end

        if existing
          existing["hooks"] = g["hooks"]
        else
          hooks[event] << g
        end
      end
    end

    existing_status = settings["statusLine"]
    if existing_status && !existing_status.dig("command").to_s.include?("plastic-")
      cache_dir = File.join(plastic_home, ".cache")
      FileUtils.mkdir_p(cache_dir)
      File.write(File.join(cache_dir, "original-statusline.json"), JSON.pretty_generate(existing_status))
    end

    settings["statusLine"] = { "type" => "command", "command" => "#{hook_dir}/plastic-statusline" }

    # No plugin/marketplace registration: skills are flat personal skills
    # (plastic-<name>/) discovered directly from ~/.claude/skills.

    write_json_atomic(settings_path, settings)
  end

  def purge_stale_plastic_hooks(hooks)
    plastic_cmd = ->(cmd) { cmd.to_s.include?("plastic-") }

    hooks.delete("statusLine")

    hooks.each do |event, groups|
      next unless groups.is_a?(Array)

      hooks[event] = groups.map do |group|
        if group.is_a?(Hash) && group["hooks"].is_a?(Array)
          group["hooks"].reject! { |h| plastic_cmd.call(h["command"]) }
          group unless group["hooks"].empty?
        elsif group.is_a?(Hash) && group["command"]
          plastic_cmd.call(group["command"]) ? nil : group
        else
          group
        end
      end.compact
    end
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
    end

    { success: true, files: removed.size, removed: removed }
  end

  def remove_claude_hooks(settings_path)
    settings = read_json_safe(settings_path)
    return unless settings && settings["hooks"]

    settings["hooks"].each do |event, groups|
      next unless groups.is_a?(Array)

      settings["hooks"][event] = groups.map do |group|
        if group.is_a?(Hash) && group["hooks"].is_a?(Array)
          group["hooks"].reject! { |h| h["command"].to_s.include?("plastic-") }
          group unless group["hooks"].empty?
        elsif group.is_a?(Hash) && group["command"]
          group["command"].to_s.include?("plastic-") ? nil : group
        else
          group
        end
      end.compact
    end

    settings["hooks"].delete_if { |_, v| v.is_a?(Array) && v.empty? }
    settings.delete("hooks") if settings["hooks"]&.empty?
    if settings.dig("statusLine", "command").to_s.include?("plastic-")
      settings.delete("statusLine")
      original_path = File.join(plastic_home, ".cache", "original-statusline.json")
      if File.exist?(original_path)
        original = JSON.parse(File.read(original_path)) rescue nil
        settings["statusLine"] = original if original
      end
    end

    # Remove from enabledPlugins
    if settings["enabledPlugins"]
      settings["enabledPlugins"].delete("plastic@plastic")
      settings.delete("enabledPlugins") if settings["enabledPlugins"].empty?
    end

    write_json_atomic(settings_path, settings)
  end

  # --- Utilities ---

  def agent_config(key)
    agents.find { |a| a[:key] == key }
  end

  def copy_dir_recursive(src, dest)
    files = []
    FileUtils.mkdir_p(dest)
    Dir.entries(src).reject { |e| e.start_with?(".") }.each do |entry|
      src_path = File.join(src, entry)
      dest_path = File.join(dest, entry)
      if File.directory?(src_path)
        files += copy_dir_recursive(src_path, dest_path)
      elsif File.file?(src_path)
        FileUtils.cp(src_path, dest_path)
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
