#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic — `update` verb. Runs via `npx @zalom/plastic update` (bin/plastic.js) or directly.
# Usage: ruby scripts/update.rb [--beta|--latest|--alpha] [--claude|--codex|--hermes|--all] [--help]
#
# Forward-only version transitions, sourced from npm dist-tags:
#   - no flag                = next version on the CURRENT channel (derived from VERSION)
#   - --beta/--latest/--alpha = switch channel. Toward stability (alpha->beta->latest) is
#                               frictionless; toward bleeding edge requires confirmation.
# "Already up to date" is a clean no-op. Performs the switch by delegating the file-sync to
# `install --reinstall --ledger-action update` for the chosen version via npx.

require_relative "lib/installer_core"
require_relative "doctor"

class Update < InstallerCore
  PKG = "@zalom/plastic"

  def cli(argv = ARGV)
    if argv.include?("--help") || argv.include?("-h")
      show_help
      return 0
    end

    iv = installed_version
    unless iv
      warn "Plastic is not installed. Run: npx #{PKG} install --claude"
      return 1
    end

    requested = requested_channel(argv)
    tags = fetch_dist_tags
    unless tags
      warn "Could not query npm dist-tags. Are you online?"
      return 1
    end

    res = compute_target(installed_version: iv, dist_tags: tags, requested_channel: requested)

    case res[:status]
    when :up_to_date
      puts "\u{2705} Plastic v#{iv} is already up to date on the #{channel_for(iv)} channel."
      return 0
    when :unknown_channel
      warn "No published version on the #{requested} channel."
      return 1
    when :ok
      if res[:kind] == :cross_bleeding && !confirm_bleeding(iv, res[:target])
        puts "Aborted."
        return 1
      end
      puts "\u{2b06}\u{fe0f}  Updating Plastic #{iv} \u{2192} #{res[:target]}"
      exit_code = perform_switch(res[:target], agent_args(argv))
      run_post_update_doctor if exit_code == 0
      exit_code
    end
  end

  # Run the full doctor after a successful update and print a human-readable
  # summary. Informational only: does not raise and does not affect the update's
  # exit code. Accepts injected `doctor` and `out` for hermetic unit tests.
  def run_post_update_doctor(doctor: nil, out: $stdout)
    doctor ||= Doctor.new
    out.puts "\nRunning full doctor after update..."
    result = doctor.run_checks("claude")
    s = result[:summary]
    out.puts "  Doctor status: #{result[:status]} " \
             "(pass: #{s[:pass]}, warn: #{s[:warn]}, fail: #{s[:fail]}, total: #{s[:total]})"
    out.puts "  Run /plastic-doctor for details." unless result[:status] == "pass"
    result
  rescue StandardError => e
    # Non-blocking: a crash here (e.g. malformed file in the real store) must not
    # undo or fail an update that already succeeded. Report and move on.
    out.puts "  doctor could not run: #{e.message} — run /plastic-doctor"
    nil
  end

  # Pure decision logic (hermetically testable). Returns a status hash.
  def compute_target(installed_version:, dist_tags:, requested_channel: nil)
    installed_ch = channel_for(installed_version)
    target_ch = requested_channel || installed_ch
    cand = dist_tags[target_ch]
    return { status: :unknown_channel } unless cand

    if target_ch == installed_ch
      return { status: :up_to_date } unless semver_gt?(cand, installed_version)
      { status: :ok, target: cand, kind: :in_channel }
    else
      bleeding = stability_rank(target_ch) < stability_rank(installed_ch)
      { status: :ok, target: cand, kind: bleeding ? :cross_bleeding : :cross_stable }
    end
  end

  def installed_version
    path = File.join(plastic_home, "VERSION")
    File.exist?(path) ? File.read(path).strip : nil
  end

  private

  def requested_channel(argv)
    return "alpha" if argv.include?("--alpha")
    return "beta" if argv.include?("--beta")
    return "latest" if argv.include?("--latest")
    nil
  end

  # Agent flags to pass through to the delegated install (default --claude).
  def agent_args(argv)
    flags = agents.map { |a| a[:flag] }.select { |f| argv.include?(f) }
    flags << "--all" if argv.include?("--all")
    flags.empty? ? ["--claude"] : flags
  end

  def fetch_dist_tags
    raw = `npm view #{PKG} dist-tags --json 2>/dev/null`
    return nil if raw.nil? || raw.strip.empty?
    JSON.parse(raw)
  rescue JSON::ParserError, StandardError
    nil
  end

  def confirm_bleeding(current, target)
    return false unless $stdin.tty?
    print "Switch from #{current} to the less-stable #{target}? [y/N]: "
    ($stdin.gets&.strip || "").downcase.start_with?("y")
  end

  # Thin npx-exec glue (not unit-tested; the decision above is). Delegates the file-sync to
  # the target version's install verb, recording the ledger action as `update`.
  def perform_switch(target, agent_flags)
    cmd = ["npx", "#{PKG}@#{target}", "install", "--reinstall", "--ledger-action", "update", *agent_flags]
    puts "  $ #{cmd.join(" ")}"
    system(*cmd) ? 0 : 1
  end

  def show_help
    puts <<~HELP

      plastic update — upgrade Plastic to a newer version

      Usage:
        npx @zalom/plastic update [options]

      Channel options (default: stay on the current channel):
        --latest      Switch to / advance the stable channel
        --beta        Switch to / advance the beta channel
        --alpha       Switch to / advance the alpha channel (bleeding edge — confirmed)

      Agent options (default: --claude):
        --claude --codex --hermes --all

      Behaviour:
        No flag advances to the next version on your current channel. Switching toward a
        more stable channel is frictionless; switching toward bleeding edge is confirmed.
        Use `versions` to roll back to a previously-installed version.

    HELP
  end
end

exit(Update.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)).cli(ARGV)) if $PROGRAM_NAME == __FILE__
