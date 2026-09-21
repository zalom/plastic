# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic session handoff` - writes this session's hand-off into the day
# ledger (`write-handoff --trigger tick`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class SessionHandoff < Command
        USAGE_LINE = "plastic session handoff [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          status = legacy.run("write-handoff", "--trigger", "tick")
          raise Failure, "write-handoff exited #{status}" unless status.zero?

          @output.next_step("plastic session summary", because: "the summary is what a fresh handoff feeds")
        end

        private

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
