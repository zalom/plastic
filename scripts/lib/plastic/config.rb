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

    # True only for the boolean true or the string "true"; `default` for a
    # missing key or a config that does not parse.
    def flag(path, default:)
      value = dig(path)
      value.nil? ? default : boolean(value, default)
    end

    private

    def boolean(value, default)
      return true if value == true || value == "true"
      return false if value == false || value == "false"

      default
    end

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
