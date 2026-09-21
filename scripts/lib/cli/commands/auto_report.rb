# frozen_string_literal: true

require_relative "intent_command"

# `plastic auto report` - an intent's completion report (`agent-report`, run
# through Legacy), then the review-by-risk rules a lead checks it against.
module Plastic
  class CLI
    module Commands
      class AutoReport < IntentCommand
        USAGE_LINE = "plastic auto report ID [--role ROLE] [--json]"

        SCRIPT = "agent-report"
        AFTER = "plastic auto lock release ID"
        BECAUSE = "closing the lock is what a delivered or abandoned report leads to"

        REVIEW_RULES = <<~TEXT.chomp
          Review by risk, boot 3, only when a rule fires; otherwise the green suite is
          the review. Dispatch the post-execution reviewer when any of these holds:
          1. the diff touches a path on the risk list (hooks, the lock, the arming
             module, the installer, a release file).
          2. a failure-mode matrix row names a test not in the diff, or a test the
             green run did not execute.
          3. the completion report carries a status other than delivered, or a
             non-empty deviations or blockers field.
          The reviewer returns a pass or fixes; at most one review-fix round, ever.
        TEXT

        def call
          super
          @output.row("review rules", REVIEW_RULES)
        end

        private

        def role
          options[:role]
        end

        def switches(parser)
          parser.on("--role ROLE") { |v| @options[:role] = v }
        end

        def script_arguments
          role ? [intent_dir, "--role", role] : [intent_dir]
        end
      end
    end
  end
end
