# frozen_string_literal: true

require_relative "../routine"
require_relative "../cli/agent_options"

module Plastic
  module Commands
    # Copies the core files of the running package into the home and
    # registers Plastic with the chosen agents.
    class Install < Routine
      graphless

      extend CLI::AgentOptions

      option :reinstall, switch: "--reinstall", default: false, text: "sync the files again for agents already registered"
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
