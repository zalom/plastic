#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic — `uninstall` verb. Runs via `npx @zalom/plastic uninstall` (bin/plastic.js) or directly.
# Usage: ruby scripts/uninstall.rb [--claude|--codex|--hermes|--all] [--help]
#
# Manifest-driven removal of installed files + legacy-plugin migration. Leaves ~/.plastic/
# (intent store, config, and the versions.json ledger) in place — the ledger is permanent.

require_relative "lib/installer_core"

class Uninstall < InstallerCore
  def cli(argv = ARGV)
    if argv.include?("--help") || argv.include?("-h")
      show_help
      return 0
    end

    selected = agent_keys_from(argv)
    selected = ["claude"] if selected.empty?

    puts "\n\u{1f9e0} Plastic v#{version} — uninstall\n\n"
    handle_uninstall(selected)
    0
  end

  private

  def show_help
    puts <<~HELP

      plastic uninstall — remove Plastic from an agent

      Usage:
        npx @zalom/plastic uninstall [options]

      Agent options:
        --claude      Uninstall from Claude Code (default)
        --codex       Uninstall from Codex CLI
        --hermes      Uninstall from Hermes
        --all         Uninstall from all supported agents

      Other options:
        -h, --help    Show this help

      Leaves your intent store, config, and version ledger (~/.plastic/) in place.

    HELP
  end
end

exit(Uninstall.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)).cli(ARGV)) if $PROGRAM_NAME == __FILE__
