# frozen_string_literal: true

require "yaml"

module Plastic
  # The home's config.yml, read once per call. A missing file, or one that
  # does not parse, reads every flag at its default: a broken config never
  # stops a hook or a command.
  class Config
    def initialize(plastic_home)
      @path = File.join(plastic_home, "config.yml")
    end

    TRUE_VALUES = [true, "true"].freeze
    FALSE_VALUES = [false, "false"].freeze

    # True for the boolean true or the string "true", false for false or
    # "false"; `default` for any other value, a missing key or a config that
    # does not parse.
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

    private

    def dig(path)
      data.dig(*path.map(&:to_s))
    rescue TypeError
      nil
    end

    def data
      @data ||= YAML.safe_load_file(@path) || {}
    rescue
      {}
    end
  end
end
