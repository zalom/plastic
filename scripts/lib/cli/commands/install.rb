# frozen_string_literal: true

require_relative "installer_verb"

# `plastic install` - wires Plastic into this machine's agents. The work is
# still scripts/install.rb, run as a child process through Legacy; this command
# is what replaces the Node shim the npm package used to carry.
module Plastic
  class CLI
    module Commands
      class Install < InstallerVerb
        USAGE_LINE = "plastic install [--claude] [--codex] [--hermes] [--all] [--reinstall] [--force] [--advisor NAME] [--no-advisor] [--statusline] [--ledger-action NAME]"
        FLAGS = %w[--claude --codex --hermes --all --reinstall --force --advisor --no-advisor --statusline --ledger-action].freeze

        SCRIPT = "install.rb"
        AFTER = "plastic version"
        BECAUSE = "the install is done, and the version proves the command works"
      end
    end
  end
end
