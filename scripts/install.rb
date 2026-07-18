#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic — `install` verb. Runs via `npx @zalom/plastic install` (bin/plastic.js) or directly.
# Usage: ruby scripts/install.rb [--claude|--codex|--hermes|--all] [--alpha|--beta|--latest] [--reinstall] [--force] [--help]
#
# One-shot by design:
#   - no install present  -> fresh install + bootstrap store
#   - already installed   -> refuse (point at `update` / `--reinstall`)
#   - --reinstall         -> re-sync core files for the installed version (repair); store untouched
#
# `update` and `versions` delegate their file-sync here via `--reinstall --ledger-action <action>`,
# so install.rb is the single file-syncer; the ledger action is contextual.

require_relative "lib/installer_core"
require_relative "lib/preflight"

class Install < InstallerCore
  def cli(argv = ARGV)
    if argv.include?("--help") || argv.include?("-h")
      show_help
      return 0
    end

    gate = preflight_gate
    return gate unless gate.zero?

    force = argv.include?("--force")
    reinstall = argv.include?("--reinstall")
    ledger_action = flag_value(argv, "--ledger-action")

    selected = agent_keys_from(argv)
    selected = prompt_agents if selected.empty?
    if selected.empty?
      puts "No agents selected. Nothing to do."
      return 0
    end

    puts "\n\u{1f9e0} Plastic v#{version}\n\n"

    if installed? && !reinstall
      # `installed?` is a GLOBAL check (is Plastic core installed for ANY
      # harness), so it cannot by itself decide whether to refuse: once any
      # agent is present, a machine that has NEVER installed a second harness
      # (e.g. Codex, with no ~/.agents, no ~/.codex/hooks.json) must still be
      # able to add it. Refuse only when EVERY selected agent already has its
      # own registration (intent 198, D7); otherwise proceed with just the
      # unregistered ones, and report the already-registered ones without
      # silently re-syncing them (that is what --reinstall is for).
      new_agents = selected.reject { |key| agent_installed?(key) }
      if new_agents.empty?
        warn "Plastic v#{installed_version} is already installed."
        warn "  - To upgrade:        npx @zalom/plastic update"
        warn "  - To re-sync files:  npx @zalom/plastic install --reinstall"
        return 1
      end

      already_registered = selected - new_agents
      run(selected: new_agents, force: force, reinstall: reinstall, ledger_action: ledger_action, argv: argv,
          already_registered: already_registered)
      return 0
    end

    run(selected: selected, force: force, reinstall: reinstall, ledger_action: ledger_action, argv: argv)
    0
  end

  # Hermetic entrypoint (no prompting / no exit). Returns the per-agent results array.
  # `already_registered` names agents the gate above found already registered:
  # they are reported, never re-installed, so the summary line and the Codex
  # trust reminder only ever count agents that actually changed this run.
  def run(selected:, force: false, reinstall: false, ledger_action: nil, argv: ARGV, input: $stdin,
          already_registered: [])
    fresh = !installed?
    mode = fresh ? :install : :update # :update here means "re-sync, skip bootstrap"

    distribute(mode)
    bootstrap if fresh
    apply_config_flags(argv)

    results = selected.map { |key| transactional_install_for_agent(key, force, argv: argv, input: input, reinstall: reinstall) }
    results += already_registered.map { |key| already_registered_result(key) }

    action = ledger_action || (fresh ? "install" : "reinstall")
    ledger_append(version, action)

    print_results(results, fresh ? :install : :reinstall)
    results
  end

  def installed?
    File.exist?(File.join(plastic_home, "VERSION"))
  end

  def installed_version
    path = File.join(plastic_home, "VERSION")
    File.exist?(path) ? File.read(path).strip : nil
  end

  # Injectable pre-flight gate: real probes as default args, printing to an
  # injectable `out:` IO so this is hermetically testable via StringIO. Returns
  # 1 (stop the install) when Ruby is missing/too-old, else 0.
  def preflight_gate(ruby_version: RUBY_VERSION, node_version: node_probe, git_present: git_probe,
                      mise_present: mise_probe, out: $stderr)
    result = Preflight.check(ruby_version: ruby_version, node_version: node_version,
                              git_present: git_present, mise_present: mise_present)
    result[:messages].each { |message| out.puts(message) }
    result[:fatal] ? 1 : 0
  end

  private

  def node_probe
    `node --version`.strip
  rescue StandardError
    ""
  end

  def git_probe
    !`command -v git`.strip.empty?
  rescue StandardError
    false
  end

  def mise_probe
    !`command -v mise`.strip.empty?
  rescue StandardError
    false
  end

  def flag_value(argv, name)
    i = argv.index(name)
    return nil unless i && argv[i + 1]
    argv[i + 1]
  end

  def already_registered_result(key)
    config = agent_config(key)
    { agent: config[:name], success: false, already_registered: true }
  end

  def print_results(results, mode)
    puts "\n\u{2014} Results \u{2014}\n\n"
    results.each do |r|
      if r[:already_registered]
        puts "  \u{2139}  #{r[:agent]}: already registered, not re-synced (use --reinstall to re-sync)"
      elsif r[:success]
        puts "  \u{2705} #{r[:agent]}: #{r[:files]} files installed"
      else
        puts "  \u{26a0}\u{fe0f}  #{r[:agent]}: #{r[:reason]}"
      end
    end

    print_agent_summary(results)

    installed = results.select { |r| r[:success] }
    return unless installed.any?

    verb = mode == :reinstall ? "re-synced" : "installed"
    puts "\n\u{2705} Plastic v#{version} #{verb}."
    puts "   Registered for: #{installed.map { |r| r[:agent] }.join(", ")}"
    puts "   Run /clear (or restart your agent) to pick up new conventions."
    puts "   Next: read docs/guides/your-first-intent-in-10-minutes.md\n\n"

    print_codex_hook_trust_reminder(installed)
  end

  # Per-agent transaction summary (intent 210, D3): agent | from -> to | ok/failed.
  # Skipped for a run with only one result, where the line above already says it all.
  def print_agent_summary(results)
    return if results.size <= 1

    puts "\n  Agent          From \u{2192} To            Result"
    puts "  -----          -----------      ------"
    results.each do |r|
      from = r[:from_version] || "-"
      to = r[:to_version] || "-"
      status = r[:already_registered] ? "skipped" : (r[:success] ? "ok" : "failed")
      puts format("  %-14s %-16s %s", r[:agent], "#{from} \u{2192} #{to}", status)
    end
  end

  # Codex hooks are installed but INERT until a human reviews and trusts each
  # hook definition via /hooks (intent 198, Decision D2); Codex keys trust to
  # the hook's current command hash, so a future release that changes a hook
  # command re-arms the review. Printed only when a harness that declares its
  # own home_dir (Codex today) actually installed successfully in this run.
  # Data-driven from `agents`, never a hardcoded harness name, mirroring the
  # same reasoning as the D1 presence-probe fix.
  def print_codex_hook_trust_reminder(installed)
    codex_like = agents.select { |a| a.key?(:home_dir) }
    return if codex_like.none? { |a| installed.any? { |r| r[:agent] == a[:name] } }

    puts "   Codex: open Codex, run /hooks, and trust the Plastic hook definitions."
    puts "   Plastic's gates will not fire until you do.\n\n"
  end

  def show_help
    puts <<~HELP

      plastic install — install or re-sync Plastic for an agent

      Usage:
        npx @zalom/plastic install [options]

      Agent options:
        --claude      Install for Claude Code
        --codex       Install for Codex CLI
        --hermes      Install for Hermes
        --all         Install for all supported agents

      Channel options:
        --latest      Stable channel (default)
        --beta        Beta channel
        --alpha       Alpha channel

      Other options:
        --reinstall          Re-sync core files for the installed version (repair). Store untouched.
        --force              Overwrite existing files without prompting
        --statusline VALUE   keep or plastic. If an existing statusline is found, this
                             skips the interactive prompt. Interactive sessions ask by
                             default; non-interactive sessions default to keep.
        --no-advisor         Skip installing both advisor agents and the agent-advisor
                             skill (advisor.enabled: false)
        --advisor VALUE      Which advisor agent is the default: an agent name, or the
                             shorthand "real" (plastic-advisor) or "faux"
                             (plastic-faux-advisor). Writes advisor.claude.default. Left
                             unset, the agent-advisor skill falls back to
                             plastic-faux-advisor at consult time.
        -h, --help           Show this help

      Notes:
        Install is one-shot. If Plastic is already installed, use `update` to upgrade or
        `install --reinstall` to repair. To change versions, use `update` / `versions`.

    HELP
  end
end

exit(Install.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__),
                 plastic_home: ENV.fetch("PLASTIC_HOME") { InstallerCore::DEFAULT_PLASTIC_HOME }).cli(ARGV)) if $PROGRAM_NAME == __FILE__
