# frozen_string_literal: true

require_relative "intent_command"

# `plastic auto brief` - an intent's spawn preamble (`spawn-preamble`, run
# through Legacy). `--role advisor` also prints the three shapes an advisor
# request takes, so a dispatching lead never has to look them up.
module Plastic
  class CLI
    module Commands
      class AutoBrief < IntentCommand
        USAGE_LINE = "plastic auto brief ID [--role ROLE] [--json]"

        SCRIPT = "spawn-preamble"
        AFTER = "plastic auto report ID"
        BECAUSE = "the report closes the turn the preamble opened"

        ADVISOR_SHAPES =
          "State the shape you need: a verdict plus the biggest risk for one bounded " \
          "decision; a stepped plan plus a risk map for a plan or plan review; rival " \
          "approaches and kill criteria for architecture, one-way doors, or deadlocks."

        def call
          super
          @output.row("advisor request shapes", ADVISOR_SHAPES) if role == "advisor"
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
