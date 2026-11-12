# frozen_string_literal: true

require_relative "../config"
require_relative "../../cli/command"
require_relative "../config_scope"

module Plastic
  module Commands
    class Config
      # Prints the value of one setting. It writes nothing.
      class Get < CLI::Command
        include ConfigScope

        argument :key, label: "KEY", text: "the setting, as its dotted name"

        def call
          key = parsed[:key]
          output.row(key, current(key).to_s)
          output.next_step("plastic config set #{key} VALUE#{harness_words}", because: "the setting is printed")
        end
      end
    end
  end
end
