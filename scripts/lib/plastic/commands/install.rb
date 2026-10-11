# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Copies the core files of the running package into the home and makes
    # the global store. `plastic init` installs Plastic into the harnesses.
    class Install < Routine
      opens_no_store

      option :reinstall, switch: "--reinstall", default: false,
        text: "sync the files again and make the global store and local.db when they are missing or behind"
      option :force, switch: "--force", default: false, text: "replace agent files Plastic did not write"
      option :dry_run, switch: "--dry-run", default: false, text: "list what would change and change nothing"

      workflow :code_preview_install do
        on :done, next: :noop
        on :continue, next: :code_install_plastic
      end
      workflow :code_install_plastic, next: :agent_offer_enola
      workflow :agent_offer_enola, next: :noop
    end
  end
end
