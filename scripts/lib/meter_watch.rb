# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "yaml"
require "time"
require "fileutils"
require "rbconfig"
require_relative "atomic_write"

# MeterWatch (intent 355, n5, D6): reads the owner's rate-limit cache on a
# timer and writes one state file a session watches, instead of every session
# parsing the cache and re-deriving the thresholds for itself. No model call
# is spent on a tick that leaves the state unchanged.
#
# Everything is injected: home (holds config.yml and .cache/), the clock, the
# cache path, and the renamer AtomicWrite uses. Nothing reads ENV, nothing
# calls launchctl, and --install-timer (scripts/meter-watch) only ever writes
# under the injected home.
class MeterWatch
  DEFAULT_REDUCE_AT = 55
  DEFAULT_STOP_AT = 85
  DEFAULT_WEEKLY_STOP_AT = 97
  TICK_SECONDS = 20 * 60
  STALE_AFTER_SECONDS = TICK_SECONDS * 2

  def initialize(home:, cache_path: nil, config_path: nil, now: Time.now, renamer: File.method(:rename))
    @home = home
    @cache_path = cache_path || File.join(home, ".cache", "rate-limits.json")
    @config_path = config_path || File.join(home, "config.yml")
    @state_path = File.join(home, ".cache", "meter-state.json")
    @now = now
    @renamer = renamer
    @reduce_at, @stop_at, @weekly_stop_at = load_thresholds
  end

  attr_reader :state_path

  def tick
    previous = read_state
    state = compute_state(previous)
    write_if_changed(previous, state)
  end

  private

  def compute_state(previous)
    return base_state("unavailable") unless File.file?(@cache_path)
    return stopped?(previous) ? previous : base_state("stale") if stale?

    cache = JSON.parse(File.read(@cache_path))
    five_hour = cache["five_hour"]
    seven_day = cache["seven_day"]
    resets_at = cache["resets_at"]

    # Resume compares `now` against the STOP's OWN resets_at (carried
    # forward on `previous`, from the tick that first wrote "stop"), never
    # the cache's current resets_at: the cache moves resets_at on to the
    # NEXT window before five_hour/seven_day themselves drop, so comparing
    # against the live value would never report resume (B4).
    label = if stopped?(previous) && reset_passed?(previous["resets_at"])
              "resume"
            else
              classify(five_hour, seven_day)
            end

    base_state(label, five_hour: five_hour, seven_day: seven_day, resets_at: resets_at)
  rescue JSON::ParserError
    base_state("unavailable")
  end

  def stopped?(previous)
    previous && previous["state"] == "stop"
  end

  def classify(five_hour, seven_day)
    return "stop" if five_hour.to_f >= @stop_at
    return "stop" if seven_day.to_f >= @weekly_stop_at
    return "reduce" if five_hour.to_f >= @reduce_at

    "ok"
  end

  def stale?
    File.mtime(@cache_path) < (@now - STALE_AFTER_SECONDS)
  rescue Errno::ENOENT
    true
  end

  def reset_passed?(resets_at)
    at = parse_time(resets_at)
    at && @now >= at
  end

  def parse_time(value)
    return nil if value.nil? || value.to_s.empty?

    text = value.to_s
    text.match?(/\A\d+\z/) ? Time.at(text.to_i).utc : Time.iso8601(text)
  rescue ArgumentError, TypeError
    nil
  end

  def base_state(label, five_hour: nil, seven_day: nil, resets_at: nil)
    {
      "state" => label,
      "five_hour" => five_hour,
      "seven_day" => seven_day,
      "resets_at" => resets_at,
      "checked_at" => @now.getutc.iso8601,
    }
  end

  def write_if_changed(previous, state)
    return state if previous && previous["state"] == state["state"]

    FileUtils.mkdir_p(File.dirname(@state_path))
    AtomicWrite.write(@state_path, JSON.generate(state), renamer: @renamer)
    state
  end

  def read_state
    return nil unless File.file?(@state_path)

    JSON.parse(File.read(@state_path))
  rescue JSON::ParserError
    nil
  end

  def load_thresholds
    config = File.file?(@config_path) ? (YAML.safe_load(File.read(@config_path)) || {}) : {}
    meter = config["meter"].is_a?(Hash) ? config["meter"] : {}
    [
      meter.fetch("reduce_at", DEFAULT_REDUCE_AT),
      meter.fetch("stop_at", DEFAULT_STOP_AT),
      meter.fetch("weekly_stop_at", DEFAULT_WEEKLY_STOP_AT),
    ]
  end

  class << self
    # Writes the LaunchAgent plist under an injectable home; never loads it
    # with launchctl (scripts/meter-watch --install-timer calls this and
    # nothing else). RunAtLoad primes the first tick; StartInterval repeats
    # it every 20 minutes.
    #
    # `label:` and `arguments:` (intent 340a, G7b, n3, graph.md D9) let the
    # delivery watch's own `runner watch --install-timer` reuse this one
    # writer for its `com.plastic.delivery-watch.<id>` job instead of
    # rendering plist XML a second time; their defaults reproduce today's
    # meter-watch plist byte for byte (row 3.1).
    def install_timer(home:, script_path:, ruby: RbConfig.ruby, interval: TICK_SECONDS,
                       label: "com.plastic.meter-watch", arguments: nil)
      agents_dir = File.join(home, "Library", "LaunchAgents")
      FileUtils.mkdir_p(agents_dir)
      plist_path = File.join(agents_dir, "#{label}.plist")
      args = arguments || [ruby, script_path, "--home", home]
      File.write(plist_path, plist(label, args, interval))
      plist_path
    end

    private

    def plist(label, arguments, interval)
      args_xml = arguments.map { |a| "    <string>#{a}</string>" }.join("\n")
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>#{label}</string>
          <key>ProgramArguments</key>
          <array>
        #{args_xml}
          </array>
          <key>StartInterval</key>
          <integer>#{interval}</integer>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
      XML
    end
  end
end
