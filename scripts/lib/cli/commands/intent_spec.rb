# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent spec` - an intent's state screen (`report-screen state`,
# same as `plastic intent show`), then the five rules the speccing
# conversation itself runs on, so the reply carries both without a second
# call.
module Plastic
  class CLI
    module Commands
      class IntentSpec < IntentCommand
        USAGE_LINE = "plastic intent spec ID [--json]"

        SCRIPT = "report-screen"
        AFTER = 'plastic intent rule ID "TEXT"'
        BECAUSE = "a ruling is recorded the moment it lands, never batched"

        RULES = [
          "1. context first: read the project state and the intent's Context and Insights",
          "2. assess scope: several independent subsystems become separate thinking conversations",
          "3. one question per message, in prose; look at the code before asking how something works",
          "4. propose two or three approaches, trade-offs first, leading with the recommendation",
          "5. present the design in sections scaled to complexity; get a ruling after each section",
          "6. record every ruling the instant it lands, never batched:",
          '   plastic intent rule ID "<ruling text>"',
          "7. a later ruling that conflicts with an earlier one gets a new insight naming it superseded",
          "8. both rulings stay on record; the later one wins",
        ].freeze

        def call
          super
          @output.row("rules", RULES)
        end

        private

        def script_arguments
          ["state", intent_dir]
        end
      end
    end
  end
end
