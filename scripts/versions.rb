#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic — `versions` verb. Runs via `npx @zalom/plastic versions` (bin/plastic.js) or directly.
# Usage: ruby scripts/versions.rb [--downgrade [--version <v>] | --upgrade] [--help]
#
# Local time-machine over the append-only versions.json ledger. Navigates ONLY versions you
# have actually run (the ledger), never npm's full list — fetching brand-new versions is
# `update`'s job. Lets you roll back to a known-good build after a bad release.
#   - no flag                  print the ledger table (and offer to continue a rollback)
#   - --downgrade              step back one version in your history
#   - --downgrade --version V  jump to a specific previously-run version
#   - --upgrade                step forward one version (after a rollback)

require_relative "lib/installer_core"

class Versions < InstallerCore
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

    if argv.include?("--downgrade")
      explicit = flag_value(argv, "--version")
      target = explicit || step_target(timeline, current, :back)
      return no_target("No earlier version in your history.") unless target
      unless timeline.include?(target)
        warn "#{target} is not in your version history. Choose one of: #{timeline.join(", ")}"
        return 1
      end
      return switch_to(target, current)
    elsif argv.include?("--upgrade")
      target = step_target(timeline, current, :forward)
      return no_target("No later version in your history. Use `update` for new releases.") unless target
      return switch_to(target, current)
    end

    # No flag: show the table, and detect an in-progress rollback.
    print_table(ledger, current)
    if ledger.last && ledger.last["action"] == "downgrade"
      prev = step_target(timeline, current, :back)
      if prev && $stdin.tty?
        print "\nYou recently rolled back. Go back further to #{prev}? [y/N]: "
        return switch_to(prev, current) if ($stdin.gets&.strip || "").downcase.start_with?("y")
      end
    end
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

  def no_target(msg)
    puts msg
    0
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

      plastic versions — manage and roll back your local Plastic versions

      Usage:
        npx @zalom/plastic versions [options]

      Options:
        (none)                  Show the version-history table
        --downgrade             Roll back one version in your history
        --downgrade --version V Roll back to a specific previously-run version
        --upgrade               Step forward one version in your history
        -h, --help              Show this help

      Navigates only versions you have already run (the append-only ledger). To move to a
      brand-new release, use `update`.

    HELP
  end
end

exit(Versions.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)).cli(ARGV)) if $PROGRAM_NAME == __FILE__
