# frozen_string_literal: true

require_relative "installer_verb"

# `plastic rollback` - steps back to a version this machine has already run. The
# work is still scripts/rollback.rb, run through Legacy.
module Plastic
  class CLI
    module Commands
      class Rollback < InstallerVerb
        USAGE_LINE = "plastic rollback [--version VERSION] [--downgrade] [--upgrade] [--reinstall]"
        FLAGS = %w[--version --downgrade --upgrade --reinstall].freeze

        SCRIPT = "rollback.rb"
        AFTER = "plastic version"
        BECAUSE = "the version says which build is installed"
      end
    end
  end
end
