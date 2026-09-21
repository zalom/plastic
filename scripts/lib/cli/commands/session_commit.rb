# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic session commit` - one commit for a verified checklist item, on the
# directory this command was invoked from (`session-commit --cwd DIR
# --summary SUMMARY`, run through Legacy; fail-open by contract, so a Failure
# here means the script's own usage error, not a git failure).
module Plastic
  class CLI
    module Commands
      class SessionCommit < Command
        USAGE_LINE = 'plastic session commit "SUMMARY" [--json]'

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SUMMARY is required" if summary.to_s.empty?

          status = legacy.run("session-commit", "--cwd", @directory, "--summary", summary)
          raise Failure, "session-commit exited #{status}" unless status.zero?

          @output.next_step("plastic session handoff", because: "a handoff after a commit keeps the day ledger current")
        end

        private

        def summary
          arguments.first
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
