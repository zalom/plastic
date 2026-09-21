# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent verify` - the merge-gate checks one intent needs before a
# close is trustworthy (`verify-intent`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class IntentVerify < IntentCommand
        USAGE_LINE = "plastic intent verify ID [--json]"

        SCRIPT = "verify-intent"
        AFTER = 'plastic intent end ID --delivered --summary "TEXT"'
        BECAUSE = "a clean verify is what makes the close trustworthy"

        private

        def script_arguments
          intent_dir
          ["--store", scope.store, "--id", id]
        end
      end
    end
  end
end
