# frozen_string_literal: true

require_relative "installer_verb"

# `plastic uninstall` - removes Plastic from this machine's agents and leaves
# the store alone. The work is still scripts/uninstall.rb, run through Legacy.
module Plastic
  class CLI
    module Commands
      class Uninstall < InstallerVerb
        USAGE_LINE = "plastic uninstall [--claude] [--codex] [--hermes] [--all]"
        FLAGS = %w[--claude --codex --hermes --all].freeze

        SCRIPT = "uninstall.rb"
        AFTER = "none"
        BECAUSE = "Plastic is removed from this machine's agents"
      end
    end
  end
end
