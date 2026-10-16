# frozen_string_literal: true

require "yaml"
require_relative "harnesses"
require_relative "config/defaults"
require_relative "config/layout"
require_relative "config/document"

module Plastic
  # The home's config.yml, read once per call: the shipped defaults, then the
  # file's `global` section, then the section of the harness, when one is
  # named. A missing file, or one that does not parse, reads every setting at
  # its default: a broken config never stops a hook or a command. See
  # docs/guide/getting-started/configuration.md.
  class Config
    TRUE_VALUES = [true, "true"].freeze
    FALSE_VALUES = [false, "false"].freeze

    def initialize(plastic_home, harness: nil)
      @path = File.join(plastic_home, "config.yml")
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

    def settings = (@settings ||= Config.merged(shipped, overrides))

    def overrides = Config.merged(section("global"), @harness ? section("harnesses", @harness) : {})

    def entries = Config.flattened(settings)

    def set(key, value) = Document.new(@path).set(key.split("."), value, harness: @harness)

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

    def section(*keys) = Layout.within(sections, *keys)

    def sections = (@sections ||= Layout.new(data).sections)

    def data
      YAML.safe_load_file(@path, aliases: true)
    rescue
      {}
    end
  end
end
