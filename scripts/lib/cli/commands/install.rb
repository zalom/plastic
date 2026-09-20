# encoding: UTF-8
# frozen_string_literal: true

require_relative "installer_verb"

# `plastic install` - wires Plastic into this machine's agents. The work is
# still scripts/install.rb, run as a child process through Legacy; this command
# is what replaces the Node shim the npm package used to carry.
module Plastic
  class CLI
    module Commands
      class Install < InstallerVerb
        USAGE_LINE = "plastic install [--claude] [--codex] [--dry-run]"

        SCRIPT = "install.rb"
        AFTER = "plastic version"
        BECAUSE = "the install is done, and the version proves the command works"
      end
    end
  end
end
