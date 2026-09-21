# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# Plastic::CLI::Commands::IntentCommand (intent 372, family 2) - the shared
# base every `plastic intent ...` subcommand runs on: it turns the positional
# id into an intent directory through Scope, runs the one script the
# subclass names, and prints the `next:`/`because:` trailer the plan calls
# for. A subcommand that needs more than that (extra usage checks, printed
# guidance, a different script-exit contract) overrides `call`.
#
# An id that resolves to no intent directory answers `NotFound` (a `Failure`
# a caller can tell apart): the row and the next: line are already on the
# output stream before it raises, so the reply reads like an ordinary
# command that found nothing rather than a crash - `plastic: <message>`
# alone.
module Plastic
  class CLI
    module Commands
      class IntentCommand < Command
        NotFound = Class.new(Failure)

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def self.call(...)
          command = new(...)
          command.call
          command.flush
          OK
        rescue OptionParser::ParseError, Scope::UnknownProject, Usage => e
          command.output.usage(e.message, self::USAGE_LINE)
          USAGE
        rescue NotFound
          command.flush
          FAILED
        rescue Refusal => e
          command.output.refused(e.message)
          REFUSED
        rescue Failure => e
          command.output.failed(e.message)
          FAILED
        end

        def call
          status = legacy.run(self.class::SCRIPT, *script_arguments)
          raise Failure, "#{self.class::SCRIPT} exited #{status}" unless status.zero?

          @output.next_step(self.class::AFTER.sub("ID", id.to_s), because: self.class::BECAUSE)
        end

        private

        def id
          arguments.first
        end

        def intent_dir
          return @intent_dir if defined?(@intent_dir)

          @intent_dir = scope.intent_dir(id)
          return @intent_dir if @intent_dir

          @output.row("intent", "no intent named #{id.inspect} in #{scope.slug}")
          @output.next_step("plastic status", because: "the id does not exist, so status can find what does")
          raise NotFound, "no intent named #{id.inspect}"
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end

        def script_arguments
          raise NoMethodError, "#{self.class} must define script_arguments"
        end
      end
    end
  end
end
