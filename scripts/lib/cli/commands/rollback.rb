# encoding: UTF-8
# frozen_string_literal: true

require_relative "installer_verb"

# `plastic rollback` - steps back to a version this machine has already run. The
# work is still scripts/rollback.rb, run through Legacy.
module Plastic
  class CLI
    module Commands
      class Rollback < InstallerVerb
        USAGE_LINE = "plastic rollback [VERSION] [--list]"

        SCRIPT = "rollback.rb"
        AFTER = "plastic version"
        BECAUSE = "the rollback is done, and the version says where it landed"
      end
    end
  end
end
