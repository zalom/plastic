# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# Shared resolution for config_asks.yml: a shipped, declarative manifest that
# lets a release announce a brand new config question without editing
# update.rb, doctor.rb, or any skill. Sibling of deprecations.yml (announce
# only); this one also tracks whether the user has answered or dismissed each
# entry, via config_asks_dismissed (mirrors deprecations_dismissed).
module ConfigAsks
  FILENAME = "config_asks.yml"

  # All declared entries, or [] if the manifest is missing or malformed.
  def self.load_entries(plastic_home)
    path = File.join(plastic_home, FILENAME)
    return [] unless File.exist?(path)

    data = YAML.safe_load(File.read(path)) || {}
    entries = data["config_asks"]
    entries.is_a?(Array) ? entries : []
  rescue StandardError
    []
  end

  # Entries whose key is unset in config.yml AND whose id is not dismissed.
  # Deliberately ignores "introduced" -- see the schema comment in
  # config_asks.yml for why (retro-fire).
  def self.pending(plastic_home)
    config = load_config(plastic_home)
    dismissed = Array(config["config_asks_dismissed"])

    load_entries(plastic_home).select do |entry|
      next false if dismissed.include?(entry["id"])

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
