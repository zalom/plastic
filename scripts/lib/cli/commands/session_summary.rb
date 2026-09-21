# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic session summary` - the block SessionStart injects at boot: open
# items, the last five done, live auto intents, other active sessions
# (`day-summary`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class SessionSummary < Command
        USAGE_LINE = "plastic session summary [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          status = legacy.run("day-summary")
          raise Failure, "day-summary exited #{status}" unless status.zero?

          @output.next_step("plastic status", because: "the board is where the summary's open items are worked from")
        end

        private

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
