# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic session commit` - records one verified checklist item as an "Item"
# savepoint line and prints the instruction for landing it (`session-commit
# --cwd DIR --summary SUMMARY [--ref REF]`, run through Legacy). Plastic runs
# no version control command: the instruction, not a git commit, is this
# command's `next:` line, the same text whether run for a human or an agent.
module Plastic
  class CLI
    module Commands
      class SessionCommit < Command
        USAGE_LINE = 'plastic session commit "SUMMARY" [--ref REF] [--json]'
        BECAUSE = "Plastic runs no version control command; this names the exact one that lands the item"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SUMMARY is required" if summary.to_s.empty?

          args = ["--cwd", @directory, "--summary", summary]
          args.push("--ref", options[:ref]) if options[:ref]

          instruction, status = legacy.capture("session-commit", *args)
          raise Failure, "session-commit exited #{status}" unless status.zero?

          @output.next_step(instruction.to_s.strip, because: BECAUSE)
        end

        private

        def switches(parser)
          parser.on("--ref REF") { |value| @options[:ref] = value }
        end

        def summary
          arguments.first
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner, output: @output, json: options[:json])
        end
      end
    end
  end
end
