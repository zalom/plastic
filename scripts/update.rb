#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic — `update` verb. Runs via `plastic update` or directly.
# Usage: ruby scripts/update.rb [--beta|--latest|--alpha] [--yes] [--claude|--codex|--hermes|--all] [--help]
#
# Forward-only version transitions, sourced from the GitHub releases list (intent 391, G5):
#   - no flag                = next version on the CURRENT channel (derived from VERSION)
#   - --beta/--latest/--alpha = switch channel. Toward stability (alpha->beta->latest) is
#                               frictionless; toward bleeding edge requires confirmation.
# "Already up to date" is a clean no-op. Two runs when a download is needed (D3): the package
# already on disk (package_root) is compared against the installed VERSION first, with no
# network call. When it is already newer, the switch syncs in place through the local
# `install --reinstall --ledger-action update`, in this same Ruby process. Only when the
# package on disk is not ahead does update reach the network, via a curl-based fetch of the
# GitHub releases list; finding a newer release there, with no local copy to sync from, it
# prints the one-line install command (npm or install.sh, by install_path) and stops. The
# `next:` line says to run `plastic update` again once that command has run.

require_relative "lib/installer_core"
require_relative "lib/release_channels"
require_relative "doctor"
require_relative "lib/config_asks"
require_relative "install"

class Update < InstallerCore
  PKG = "@zalom/plastic"
  RELEASES_URL = "https://api.github.com/repos/zalom/plastic/releases?per_page=50"

  # Mirrors Doctor.default_runner: a pure factory for the real, curl-shelling fetcher, kept
  # out of the instance so a test never needs a real HTTP call to exercise update's logic.
  def self.default_release_fetcher
    lambda do
      raw = `curl -fsSL #{RELEASES_URL} 2>/dev/null`
      return nil if raw.nil? || raw.strip.empty?

      releases = JSON.parse(raw)
      return nil unless releases.is_a?(Array)

      ReleaseChannels.channels(releases)
    rescue JSON::ParserError, StandardError
      nil
    end
  end

  def cli(argv = ARGV)
    if argv.include?("--help") || argv.include?("-h")
      show_help
      return 0
    end

    iv = installed_version
    unless iv
      warn "Plastic is not installed. Run the install command your platform's docs give, then `plastic install --claude`."
      return 1
    end

    if semver_gt?(version, iv)
      # A download already ran (D3's second run): the package on disk outranks what is
      # synced into plastic_home. Sync in place, no network call needed.
      puts "\u{2b06}\u{fe0f}  Syncing Plastic #{iv} \u{2192} #{version}"
      exit_code = perform_switch(version, agent_args(argv))
      if exit_code == 0
        announce_pending_config_asks(agent_key: primary_agent_key(argv))
        run_post_update_doctor(full: argv.include?("--full-doctor"), synced_agents: target_agent_keys(argv))
      end
      return exit_code
    end

    requested = requested_channel(argv)
    channels = fetch_channels
    unless channels
      warn "Could not reach the GitHub releases list. Are you online?"
      return 1
    end

    res = compute_target(installed_version: iv, dist_tags: channels, requested_channel: requested)

    case res[:status]
    when :up_to_date
      targeted = target_agent_keys(argv)
      stale = agents_needing_sync(target: iv, agent_versions: agent_versions_for(targeted))
      if stale.empty?
        puts "\u{2705} Plastic v#{iv} is already up to date on the #{channel_for(iv)} channel."
        return 0
      end
      # Same-version repair (intent 210, D1/AC4): the core is current but a targeted
      # agent's own record is stale or missing (e.g. a harness added after the last
      # sync). Re-sync at the SAME version instead of the clean no-op above.
      puts "\u{1f527} Plastic core v#{iv} is current; repairing stale agent(s): #{stale.join(", ")}"
      exit_code = perform_switch(iv, agent_args(argv))
      if exit_code == 0
        announce_pending_config_asks(agent_key: primary_agent_key(argv))
        run_post_update_doctor(full: argv.include?("--full-doctor"), synced_agents: targeted)
      end
      exit_code
    when :unknown_channel
      warn "No published version on the #{requested} channel."
      return 1
    when :ok
      return 3 if refuse_incompatible_store_layout(res[:target])

      if res[:kind] == :cross_bleeding && !confirm_bleeding(iv, res[:target], argv)
        puts "Aborted."
        return 1
      end
      print_install_command(res[:target])
      0
    end
  end

  # Given the resolved target version and a { key => installed_version_or_nil } map for the
  # agents this update targets, return the keys that still need a sync: version behind the
  # target, or missing (nil). All-current returns []. Pure; unit-tested (intent 210, G3).
  def agents_needing_sync(target:, agent_versions:)
    agent_versions.select { |_k, v| v.nil? || semver_gt?(target, v) }.keys
  end

  # Print any pending config question(s) straight to stdout, right after a
  # successful perform_switch (the moment the NEW config_asks.yml and
  # write-config just landed on disk via the target versions own
  # `install --reinstall`). Informational only, like run_post_update_doctor:
  # rescued so a crash here can never undo or fail an update that already
  # succeeded, and never changes the exit code this methods caller returns.
  #
  # A manifest that exists but cannot be read or parsed still prints
  # something visible (the problem itself), it never prints nothing: a
  # missing manifest is a legitimate quiet no-op, an unreadable one is not.
  # agent_key defaults to "claude" and should be the agent this update is
  # actually installing for, so an entry scoped to a different agent is not
  # announced here.
  def announce_pending_config_asks(agent_key: "claude", out: $stdout)
    manifest_problem = ConfigAsks.manifest_error(plastic_home)
    if manifest_problem
      out.puts "\nCould not check for pending config questions: #{manifest_problem}"
      return
    end

    pending = ConfigAsks.pending(plastic_home, agent_key)
    return if pending.empty?

    out.puts "\nConfig question(s) introduced by this update:"
    pending.each do |entry|
      out.puts "  #{entry["question"]} (id: #{entry["id"]})"
      Array(entry["options"]).each do |opt|
        out.puts "    - #{opt["label"]}"
        out.puts "      #{ConfigAsks.write_config_command(plastic_home, entry["key"], opt["value"])}"
      end
      out.puts "    - Not now (keep the default)"
      out.puts "      #{ConfigAsks.dismiss_command(plastic_home, entry["id"])}"
    end
  rescue StandardError => e
    out.puts "  could not check config asks: #{e.message}"
  end

  # Run doctor after a successful update and print a human-readable summary, once per
  # synced agent (intent 210, C5: a Codex-only or --all update must not always report
  # only claude). Defaults to the fast core tier (agent registration + core files +
  # manifest sync, binary pass|fail, no store walk) so a newcomer's first post-update
  # run is not buried in convention warns they cannot act on. `full: true`
  # (via `--full-doctor`) runs the complete store walk instead. Informational
  # only: does not raise and does not affect the update's exit code. Accepts
  # injected `doctor` and `out` for hermetic unit tests. Returns the single result hash
  # when exactly one agent was checked (matches the pre-210 return shape), else an
  # array of per-agent result hashes.
  def run_post_update_doctor(doctor: nil, out: $stdout, full: false, synced_agents: ["claude"])
    doctor ||= Doctor.new
    keys = synced_agents.nil? || synced_agents.empty? ? ["claude"] : synced_agents
    out.puts full ? "\nRunning full doctor after update..." : "\nRunning core doctor after update..."
    results = keys.map do |key|
      result = full ? doctor.run_checks(key) : doctor.run_core_checks(key)
      s = result[:summary]
      out.puts "  [#{key}] Doctor status: #{result[:status]} " \
               "(pass: #{s[:pass]}, warn: #{s[:warn]}, fail: #{s[:fail]}, total: #{s[:total]})"
      out.puts "  Run /plastic-doctor for details." unless result[:status] == "pass"
      result
    end
    keys.size == 1 ? results.first : results
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

  # Agent keys this invocation targets (intent 210, D1/G3): explicit flags in argv, or
  # --all, or, when no flag was given at all, every currently-installed agent (never a
  # hardcoded Claude-only default). Single source of truth for both agent_args (the
  # argv fragment forwarded to the delegated install) and the same-version repair check.
  def target_agent_keys(argv)
    return agents.map { |a| a[:key] } if argv.include?("--all")

    explicit = agents.select { |a| argv.include?(a[:flag]) }.map { |a| a[:key] }
    return explicit unless explicit.empty?

    installed = installed_agents
    installed.empty? ? ["claude"] : installed
  end

  # Agent flags to pass through to the delegated install. No-flag resolves to every
  # installed agent's flag, not a hardcoded ["--claude"] (intent 210, AC3).
  def agent_args(argv)
    target_agent_keys(argv).map { |k| agents.find { |a| a[:key] == k }[:flag] }
  end

  # { key => installed_version_or_nil } for the given agent keys, read from each
  # agent's own record (intent 210, D1).
  def agent_versions_for(keys)
    keys.each_with_object({}) { |k, h| h[k] = agent_version_for(agent_config(k)) }
  end

  # The single agent key this update is installing for, for config_asks
  # scoping purposes: the first explicitly-flagged agent found in argv, or
  # "claude" (matches agent_args' own default, and covers --all / no flag).
  def primary_agent_key(argv)
    match = agents.find { |a| argv.include?(a[:flag]) }
    match ? match[:key] : "claude"
  end

  def fetch_channels(fetcher: self.class.default_release_fetcher)
    fetcher.call
  end

  # A root under `node_modules` is an npm install; any other root is install.sh (spec G5).
  def install_path(root = package_root)
    root.to_s.include?("node_modules") ? :npm : :install_sh
  end

  # PLASTIC_CHANNEL as install.sh reads it: "stable" for the default channel, else the
  # channel name unchanged. channel_for names the default channel "latest" (the old npm
  # dist-tag), which install.sh has never heard of.
  def channel_env(channel)
    channel == "latest" ? "stable" : channel
  end

  # No local copy of `target` exists to sync from (it came from the network, not the
  # package already on disk), so update prints the one-line command that fetches it and
  # stops. The next `plastic update` run finds the package on disk ahead of installed_version
  # and syncs in place (D3's second run).
  def print_install_command(target)
    channel = channel_for(target)
    cmd = if install_path == :npm
      "npm install -g #{PKG}@#{target}"
    else
      "curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | PLASTIC_CHANNEL=#{channel_env(channel)} sh"
    end
    puts "\u{2b06}\u{fe0f}  Plastic #{target} is available. Run:\n\n  #{cmd}\n\nThen run `plastic update` again to sync it in."
  end

  # --yes (intent 310) answers the bleeding-edge question without a tty, so a script or an
  # agent can run `update --alpha --yes`; without it a non-tty run aborts as before.
  def confirm_bleeding(current, target, argv = [])
    return true if argv.include?("--yes")
    return false unless $stdin.tty?
    print "Switch from #{current} to the less-stable #{target}? [y/N]: "
    ($stdin.gets&.strip || "").downcase.start_with?("y")
  end

  # Thin glue (the decision above is unit-tested). Delegates the file-sync to the local
  # install verb, running it in this same Ruby process (no download, no subprocess: the
  # target version's code is already on disk at package_root by construction, see cli's
  # two call sites), recording the ledger action as `update`. On success, commits the
  # re-synced core files and clears the update-check cache (former update skill, lines
  # 124-125).
  def perform_switch(target, agent_flags, switch_runner: ->(argv) { Install.new(package_root: package_root, plastic_home: plastic_home, version: version, agents: agents).cli(argv).zero? })
    argv = ["--reinstall", "--ledger-action", "update", *agent_flags]
    puts "  $ plastic install #{argv.join(" ")}"
    return 1 unless switch_runner.call(argv)
    unless installed_version == target
      warn "Update did not install #{target}; installed version is #{installed_version.inspect}."
      return 1
    end

    commit_core_files(target)
    clear_update_check_cache
    0
  end

  # Intent 372 (former update skill, lines 124-125): `~/.plastic` is its own git
  # repository (install.rb's git_init_if_absent), so a successful update commits the
  # core files it just re-synced. Empty commits are allowed: a same-version repair
  # re-syncs nothing new, and that is still worth a ledger-adjacent commit.
  def commit_core_files(target, runner: ->(cmd) { system(*cmd) })
    runner.call(["git", "-C", plastic_home, "add", "PLASTIC.md", "scripts", "AGENTS.md", "VERSION",
      "versions.json", "deprecations.yml", "config_asks.yml"])
    runner.call(["git", "-C", plastic_home, "commit", "-m", "chore: update Plastic to #{target}",
      "--allow-empty"])
  end

  def clear_update_check_cache
    FileUtils.rm_f(File.join(plastic_home, ".cache", "update-check.json"))
  end

  def show_help
    puts <<~HELP

      plastic update — upgrade Plastic to a newer version

      Usage:
        plastic update [options]

      Channel options (default: stay on the current channel):
        --latest      Switch to / advance the stable channel
        --beta        Switch to / advance the beta channel
        --alpha       Switch to / advance the alpha channel (bleeding edge — confirmed)
        --yes         Confirm a switch toward bleeding edge without a prompt (scripts, agents)

      Agent options (default: --claude):
        --claude --codex --hermes --all

      Post-update doctor:
        By default, a successful update runs the fast core doctor sync (agent
        registration, core files, manifest — binary pass|fail, no store walk).
        --full-doctor   Run the full doctor (complete store walk) after updating.

      Behaviour:
        No flag advances to the next version on your current channel. Switching toward a
        more stable channel is frictionless; switching toward bleeding edge is confirmed.
        Use `rollback` to roll back to a previously-installed version.

    HELP
  end
end

exit(Update.new(package_root: ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)).cli(ARGV)) if $PROGRAM_NAME == __FILE__
