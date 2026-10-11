# frozen_string_literal: true

require "yaml"
require_relative "../cli/command"
require_relative "config_scope"

module Plastic
  module Commands
    # Writes one setting to config.yml: under `global`, or under the
    # harness's section with --harness.
    class ConfigSet < CLI::Command
      include ConfigScope

      argument :key, label: "KEY", text: "the setting, as its dotted name"
      argument :value, label: "VALUE", text: "the new value"

      def call
        key = parsed[:key]
        value = checked(key, scalar(parsed[:value]))
        config.set(key, value)
        output.row(key, value.to_s)
        output.next_step("plastic config get #{key}#{harness_words}", because: "the setting is written")
      end

      private

      def scalar(text)
        case YAML.safe_load(text)
        in Enumerable then raise CLI::Command::Usage, "a setting takes one value, not #{text}"
        in nil then text
        in value then value
        end
      rescue Psych::Exception
        text
      end

      def checked(key, value)
        on_off = ON_OFF.include?(current(key))
        raise CLI::Command::Usage, "#{key} takes true or false" if on_off && !ON_OFF.include?(value)

        value
      end
    end
  end
end
