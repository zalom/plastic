# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# Shared resolution for config_asks.yml: a shipped, declarative manifest that
# lets a release announce a brand new config question without editing
# update.rb, doctor.rb, or any skill. Sibling of deprecations.yml (announce
# only); this one also tracks whether the user has answered or dismissed each
# entry, via config_asks_dismissed (mirrors deprecations_dismissed).
#
# Footgun for whoever adds the next entry: pending reads config.yml directly
# and never merges in read-config's DEFAULTS, so keying a new entry on
# something that already has a non-nil value in read-config's DEFAULTS would
# make that entry look unset, and therefore pending, forever, even though the
# rest of Plastic already treats it as answered by that default. See the
# matching note in config_asks.yml's schema header.
module ConfigAsks
  FILENAME = "config_asks.yml"

  # nil if the manifest is absent (a legitimate no-op: no release has declared
  # a config question yet) or valid. A short description of the problem if the
  # file exists but could not be read or parsed, or does not declare a
  # config_asks array. Callers use this to tell "nothing declared" apart from
  # "declared but broken" -- the manifest being unreadable must never look
  # like a clean pass.
  def self.manifest_error(plastic_home)
    path = File.join(plastic_home, FILENAME)
    return nil unless File.exist?(path)

    data = YAML.safe_load(File.read(path))
    return "#{FILENAME} does not declare a config_asks list" unless data.is_a?(Hash) && data["config_asks"].is_a?(Array)

    nil
  rescue StandardError => e
    "#{FILENAME} could not be read: #{e.message}"
  end

  # All declared entries, or [] if the manifest is missing or malformed. Use
  # manifest_error alongside this when the difference between "no entries"
  # and "could not read the manifest" matters (it always does for a health
  # check or an announcement -- see manifest_error above).
  def self.load_entries(plastic_home)
    path = File.join(plastic_home, FILENAME)
    return [] unless File.exist?(path)

    data = YAML.safe_load(File.read(path)) || {}
    entries = data["config_asks"]
    entries.is_a?(Array) ? entries : []
  rescue StandardError
    []
  end

  # Entries whose key is unset in config.yml AND whose id is not dismissed AND
  # whose agents (if any) include agent_key. Deliberately ignores "introduced"
  # -- see the schema comment in config_asks.yml for why (retro-fire).
  #
  # agent_key: nil means "do not filter by agent" (every entry applies); pass
  # the caller's actual agent ("claude", "codex", "hermes") to respect an
  # entry's agents scoping.
  def self.pending(plastic_home, agent_key = nil)
    config = load_config(plastic_home)
    dismissed = Array(config["config_asks_dismissed"])

    load_entries(plastic_home).select do |entry|
      next false if dismissed.include?(entry["id"])
      next false unless applies_to_agent?(entry, agent_key)

      value = dig(config, entry["key"].to_s)
      value.nil? || value == ""
    end
  end

  # The exact command that answers one option of one entry.
  def self.write_config_command(plastic_home, key, value)
    "ruby #{File.join(plastic_home, "scripts", "write-config")} #{key} #{value}"
  end

  # The exact command that dismisses one entry ("not now" / keep default).
  def self.dismiss_command(plastic_home, id)
    "ruby #{File.join(plastic_home, "scripts", "write-config")} config_asks_dismissed --push #{id}"
  end

  # An entry with no agents field (or an empty one) applies to every agent.
  # Otherwise it applies only when agent_key is nil (no filtering requested)
  # or is present in the entry's agents list.
  def self.applies_to_agent?(entry, agent_key)
    scoped = Array(entry["agents"])
    return true if scoped.empty?
    return true if agent_key.nil?

    scoped.include?(agent_key)
  end
  private_class_method :applies_to_agent?

  def self.load_config(plastic_home)
    path = File.join(plastic_home, "config.yml")
    return {} unless File.exist?(path)

    YAML.safe_load(File.read(path)) || {}
  rescue StandardError
    {}
  end
  private_class_method :load_config

  def self.dig(hash, dotted_key)
    dotted_key.split(".").reduce(hash) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
  end
  private_class_method :dig
end
