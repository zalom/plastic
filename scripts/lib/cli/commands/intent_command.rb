# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# Plastic::CLI::Commands::IntentCommand (intent 372, family 2) - the shared
# base every `plastic intent ...` subcommand runs on: it turns the positional
# id into an intent directory through Scope, runs the one script the
# subclass names, and prints the `next:`/`because:` trailer the plan calls
# for. A subcommand that needs more than that (extra usage checks, printed
# guidance, a different script-exit contract) overrides `call`.
module Plastic
  class CLI
    module Commands
      class IntentCommand < Command
        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
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

          raise Failure, "no intent #{id.inspect} in #{scope.slug}; plastic status lists the ones that exist"
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner, output: @output, json: options[:json])
        end

        def script_arguments
          raise NoMethodError, "#{self.class} must define script_arguments"
        end
      end
    end
  end
end
