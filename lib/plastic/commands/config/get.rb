# frozen_string_literal: true

require_relative "../config"
require_relative "../../routine"
require_relative "../../cli/config_scope"

module Plastic
  module Commands
    class Config
      # Prints the value of one setting. It writes nothing.
      class Get < Routine
        include CLI::ConfigScope

        argument :key, label: "KEY", text: "the setting, as its dotted name"

        workflow :code_get_config, next: :noop
      end
    end
  end
end
