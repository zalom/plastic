# frozen_string_literal: true

require_relative "../routine"
require_relative "../cli/agent_options"

module Plastic
  module Commands
    # Copies the core files of the running package into the home and
    # registers Plastic with the chosen agents.
    class Install < Routine
      opens_no_store

      extend CLI::AgentOptions

      option :reinstall, switch: "--reinstall", default: false, text: "sync the files again and make the global store and local.db when they are missing or behind"
      option :force, switch: "--force", default: false, text: "replace agent files Plastic did not write"

      workflow :code_preview_install do
        on :done, next: :noop
        on :continue, next: :code_install_plastic
      end
      workflow :code_install_plastic, next: :agent_offer_enola
      workflow :agent_offer_enola, next: :noop
    end
  end
end
