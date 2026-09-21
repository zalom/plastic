# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic feedback "TITLE"` - files a report with feedback-report, the body
# read from standard input and passed to the child process unchanged.
module Plastic
  class CLI
    module Commands
      class Feedback < Command
        USAGE_LINE = 'plastic feedback "TITLE"'

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "plastic feedback needs a title" if title.nil? || title.strip.empty?

          status = legacy.run("feedback-report", "--title", title)
          raise Failure, "feedback-report exited #{status}" unless status.zero?

          @output.next_step("none", because: "the report is saved as a draft; open the printed URL to send it")
        end

        private

        def title
          arguments.first
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
