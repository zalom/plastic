# frozen_string_literal: true

require_relative "../config"
require_relative "../../cli/command"
require_relative "../config_scope"

module Plastic
  module Commands
    class Config
      # Lists every setting with its value: the global settings, or those of
      # one harness with --harness. It writes nothing.
      class List < CLI::Command
        include ConfigScope

        def call
          config.entries.each { |key, value| output.row(key, value.to_s) }
          output.next_step("plastic config set KEY VALUE#{harness_words}", because: "the settings are listed")
        end
      end
    end
  end
end
