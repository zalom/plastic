# encoding: UTF-8
# frozen_string_literal: true

require_relative "installer_verb"

# `plastic update` - moves this machine to the next version on its channel. The
# work is still scripts/update.rb, run through Legacy.
module Plastic
  class CLI
    module Commands
      class Update < InstallerVerb
        USAGE_LINE = "plastic update [--dry-run]"

        SCRIPT = "update.rb"
        AFTER = "plastic version"
        BECAUSE = "the update is done, and the version says where it landed"
      end
    end
  end
end
