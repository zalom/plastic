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
      warn "Plastic v#{installed_version} is already installed."
      warn "  - To upgrade:        npx @zalom/plastic update"
      warn "  - To re-sync files:  npx @zalom/plastic install --reinstall"
      return 1
    end

    run(selected: selected, force: force, reinstall: reinstall, ledger_action: ledger_action, argv: argv)
    0
  end

  # Hermetic entrypoint (no prompting / no exit). Returns the per-agent results array.
  def run(selected:, force: false, reinstall: false, ledger_action: nil, argv: ARGV, input: $stdin)
    fresh = !installed?
    mode = fresh ? :install : :update # :update here means "re-sync, skip bootstrap"

    distribute(mode)
    bootstrap if fresh

    results = selected.map { |key| install_for_agent(key, force, argv: argv, input: input, reinstall: reinstall) }

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

  def print_results(results, mode)
    puts "\n\u{2014} Results \u{2014}\n\n"
    results.each do |r|
      if r[:success]
        puts "  \u{2705} #{r[:agent]}: #{r[:files]} files installed"
      else
        puts "  \u{26a0}\u{fe0f}  #{r[:agent]}: #{r[:reason]}"
      end
    end

    installed = results.select { |r| r[:success] }
    return unless installed.any?

    verb = mode == :reinstall ? "re-synced" : "installed"
    puts "\n\u{2705} Plastic v#{version} #{verb}."
    puts "   Registered for: #{installed.map { |r| r[:agent] }.join(", ")}"
    puts "   Run /clear (or restart your agent) to pick up new conventions."
    puts "   Next: read docs/guides/your-first-intent-in-10-minutes.md\n\n"
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
        -h, --help           Show this help

      Notes:
        Install is one-shot. If Plastic is already installed, use `update` to upgrade or
        `install --reinstall` to repair. To change versions, use `update` / `versions`.

    HELP
  end
end

exit(Install.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)).cli(ARGV)) if $PROGRAM_NAME == __FILE__
