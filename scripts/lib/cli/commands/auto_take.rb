# frozen_string_literal: true

require_relative "intent_command"

# `plastic auto take` - arms the intent's delivery lock for this session
# (`plastic-lock arm --intent-dir DIR --mode auto`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class AutoTake < IntentCommand
        USAGE_LINE = "plastic auto take ID [--json]"

        SCRIPT = "plastic-lock"
        AFTER = "plastic auto brief ID"
        BECAUSE = "the preamble is the live state a taken intent is read from next"

        private

        def script_arguments
          ["arm", "--intent-dir", intent_dir, "--mode", "auto"]
        end
      end
    end
  end
end
