# frozen_string_literal: true

require "yaml"
require_relative "harnesses"
require_relative "config/defaults"
require_relative "config/store"
require_relative "config/upgrade"

module Plastic
  # The settings rows of the machine database, read once per call: the shipped
  # defaults, then the `global` rows, then the rows of the harness, when one is
  # named. A database that is missing, busy or behind reads every setting at
  # its default: a broken home never stops a hook or a command. config.yml is
  # printed from the rows. See docs/reference/commands/config/README.md.
  class Config
    TRUE_VALUES = [true, "true"].freeze
    FALSE_VALUES = [false, "false"].freeze

    def initialize(plastic_home, harness: nil, clock: Time)
      @home = plastic_home
      @clock = clock
      @rows = Rows.new(plastic_home)
      @harness = harness && Harnesses.fetch(harness).name
    end

    def flag(path, default:)
      value = dig(path)
      return true if TRUE_VALUES.include?(value)
      return false if FALSE_VALUES.include?(value)

      default
    end

    def choice(path, default:, allowed:)
      value = dig(path)
      value = "off" if value == false
      allowed.include?(value) ? value : default
    end

    def value(key) = dig(key.split("."))

    # The stores a search reads when none is named: the comma value of search.source_projects.
    def source_projects = value("search.source_projects").to_s.split(",")

    def settings = (@settings ||= Config.merged(shipped, overrides))

    def overrides = Config.merged(@rows.scope("global"), @harness ? @rows.scope(@harness) : {})

    def entries = Config.flattened(settings)

    def set(key, value) = Store.new(@home, clock: @clock).set(@harness || "global", key, value)

    def self.merged(base, over)
      base.merge(over) { |_key, old, new| (old.is_a?(Hash) && new.is_a?(Hash)) ? merged(old, new) : new }
    end

    def self.flattened(hash, prefix = nil)
      hash.each_with_object({}) do |(key, value), entries|
        name = [prefix, key].compact.join(".")
        value.is_a?(Hash) ? entries.merge!(flattened(value, name)) : entries[name] = value
      end
    end

    def self.dug(hash, keys) = keys.reduce(hash) { |data, key| data[key] if data.is_a?(Hash) }

    private

    def shipped = @harness ? Config.merged(Defaults::GLOBAL, Defaults.harness(@harness)) : Defaults::GLOBAL

    def dig(path) = Config.dug(settings, path.map(&:to_s))
  end
end
