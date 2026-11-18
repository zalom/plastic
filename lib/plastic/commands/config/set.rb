# frozen_string_literal: true

require_relative "../config"
require_relative "../../routine"
require_relative "../../cli/config_scope"

module Plastic
  module Commands
    class Config
      # Writes one setting to the settings rows: under `global`, or under the
      # harness's section with --harness.
      class Set < Routine
        include CLI::ConfigScope

        argument :key, label: "KEY", text: "the setting, as its dotted name"
        argument :value, label: "VALUE", text: "the new value"

        workflow :code_set_config, next: :noop
      end
    end
  end
end
