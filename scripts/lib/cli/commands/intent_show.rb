# frozen_string_literal: true

require_relative "intent_command"
require_relative "../intent_progress"

# `plastic intent show` - an intent's state screen (`report-screen state`, run
# through Legacy).
module Plastic
  class CLI
    module Commands
      class IntentShow < IntentCommand
        USAGE_LINE = "plastic intent show ID [--json]"

        SCRIPT = "report-screen"
        AFTER = "plastic intent step ID"
        BECAUSE = "the state screen is where the next step comes from"

        def call
          super
          command, reason = IntentProgress.new(scope, id).decision
          @output.next_step(command, because: reason)
        end

        private

        def script_arguments
          ["state", intent_dir]
        end
      end
    end
  end
end
