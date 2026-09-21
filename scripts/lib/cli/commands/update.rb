# frozen_string_literal: true

require_relative "installer_verb"

# `plastic update` - moves this machine to the next version on its channel. The
# work is still scripts/update.rb, run through Legacy.
module Plastic
  class CLI
    module Commands
      class Update < InstallerVerb
        USAGE_LINE = "plastic update [--claude] [--codex] [--hermes] [--all] [--latest] [--beta] [--alpha] [--yes] [--reinstall] [--full-doctor]"
        FLAGS = %w[--claude --codex --hermes --all --latest --beta --alpha --yes --reinstall --full-doctor].freeze

        SCRIPT = "update.rb"
        AFTER = "plastic version"
        BECAUSE = "the update is done, and restarting the session picks up the new conventions"
      end
    end
  end
end
