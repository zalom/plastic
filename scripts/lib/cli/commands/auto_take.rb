# frozen_string_literal: true

require_relative "intent_command"

# `plastic auto take` - arms the intent's delivery lock for this session
# (`plastic-lock arm --intent-dir DIR --mode auto`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class AutoTake < IntentCommand
        USAGE_LINE = "plastic auto take ID [--allow-inline] [--json]"

        SCRIPT = "plastic-lock"
        AFTER = "plastic auto brief ID"
        BECAUSE = "the preamble is the live state a taken intent is read from next"

        private

        def switches(parser)
          parser.on("--allow-inline") { @options[:allow_inline] = true }
        end

        def script_arguments
          args = ["arm", "--intent-dir", intent_dir, "--mode", "auto"]
          args << "--allow-inline" if options[:allow_inline]
          args
        end
      end
    end
  end
end
