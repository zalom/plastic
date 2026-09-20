# encoding: UTF-8
# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# Plastic::CLI::Commands::InstallerVerb (intent 363) - what install, update,
# rollback and uninstall have in common: pass every argument to the installer
# script of the same name, let its output through untouched, and turn its exit
# status into one of the four codes. A subclass is four constants.
#
# The scripts stay where they are. They move into modules with the rest of the
# system family, and then Legacy goes.
module Plastic
  class CLI
    module Commands
      class InstallerVerb < Command
        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        private

        def call
          status = legacy.run(self.class::SCRIPT, *@argv)
          raise Failure, "#{self.class::SCRIPT} exited #{status}" unless status.zero?

          @output.next_step(self.class::AFTER, because: self.class::BECAUSE)
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end

        # Every argument belongs to the installer script, which has its own
        # flags and its own --help, so this command parses none of them.
        def parse
          nil
        end
      end
    end
  end
end
