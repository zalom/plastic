#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic — `rollback` verb. Runs via `npx @zalom/plastic rollback` (bin/plastic.js) or directly.
# Usage: ruby scripts/rollback.rb [--version <v> [--downgrade | --upgrade]] [--help]
#
# Local time-machine over the append-only versions.json ledger. Navigates ONLY versions you
# have actually run (the ledger), never npm's full list — fetching brand-new versions is
# `update`'s job. Lets you roll back to a known-good build after a bad release.
#   - no flag                        read-only: print the version-history table, never switch
#   - --version V                    switch to a specific previously-run version (direction derived)
#   - --downgrade --version V        synonym of --version V (direction flag is descriptive only)
#   - --upgrade --version V          synonym of --version V (direction flag is descriptive only)
#   - --downgrade / --upgrade alone  no target given: error, no switch
#
# Switching always requires an explicit --version V. A rollback tool whose job is safety
# during a bad release must never switch versions without a named target.

require_relative "lib/installer_core"

class Rollback < InstallerCore
  PKG = "@zalom/plastic"

  def cli(argv = ARGV)
    if argv.include?("--help") || argv.include?("-h")
      show_help
      return 0
    end

    ledger = ledger_read
    if ledger.empty?
      puts "No version history yet (versions.json is empty). Install or update first."
      return 0
    end

    timeline = version_timeline(ledger)
    current = installed_version || timeline.last
    explicit = flag_value(argv, "--version")

    if explicit
      unless timeline.include?(explicit)
        warn "#{explicit} is not in your version history. Choose one of: #{timeline.join(", ")}"
        return 1
      end
      return switch_to(explicit, current)
    end

    if argv.include?("--downgrade") || argv.include?("--upgrade")
      warn "An explicit target is required: pass --version <v>. Run `rollback` with no " \
           "flags to see your version history and pick a target."
      return 1
    end

    # No flags at all: read-only. Print the table and stop; never switch, never prompt.
    print_table(ledger, current)
    0
  end

  # Unique versions in first-seen (chronological) order — the user's personal timeline.
  def version_timeline(ledger)
    ledger.map { |e| e["version"] }.compact.uniq
  end

  # Neighbour of `current` in the timeline. direction :back (older) or :forward (newer).
  def step_target(timeline, current, direction)
    i = timeline.index(current)
    return nil if i.nil?
    j = direction == :back ? i - 1 : i + 1
    return nil if j < 0 || j >= timeline.length
    timeline[j]
  end

  # Direction-derived ledger action for moving current -> target.
  def action_for(target, current)
    cmp = semver_compare(target, current)
    cmp == -1 ? "downgrade" : "update"
  end

  def installed_version
    path = File.join(plastic_home, "VERSION")
    File.exist?(path) ? File.read(path).strip : nil
  end

  private

  def flag_value(argv, name)
    i = argv.index(name)
    return nil unless i && argv[i + 1]
    argv[i + 1]
  end

  def switch_to(target, current)
    action = action_for(target, current)
    puts "#{action == "downgrade" ? "\u{23ea}" : "\u{23e9}"}  #{current} \u{2192} #{target} (#{action})"
    cmd = ["npx", "#{PKG}@#{target}", "install", "--reinstall", "--ledger-action", action, "--claude"]
    puts "  $ #{cmd.join(" ")}"
    system(*cmd) ? 0 : 1
  end

  def print_table(ledger, current)
    puts "\nPlastic version history (versions.json — append-only):\n\n"
    puts "    %-22s %-10s %s" % ["version", "action", "at"]
    ledger.each do |e|
      marker = e["version"] == current ? "\u{2192} " : "  "
      puts "  #{marker}%-22s %-10s %s" % [e["version"], e["action"], e["at"]]
    end
    puts "\n  \u{2192} = currently installed (v#{current})\n\n"
  end

  def show_help
    puts <<~HELP

      plastic rollback — read installed and available versions, and switch on request

      Usage:
        npx @zalom/plastic rollback [options]

      Options:
        (none)                    Show the version-history table (read-only, no switch)
        --version V                Switch to version V (direction derived automatically)
        --downgrade --version V    Synonym of --version V
        --upgrade --version V      Synonym of --version V
        -h, --help                 Show this help

      Switching always requires an explicit --version V. Navigates only versions you have
      already run (the append-only ledger). To move to a brand-new release, use `update`.

    HELP
  end
end

exit(Rollback.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)).cli(ARGV)) if $PROGRAM_NAME == __FILE__
