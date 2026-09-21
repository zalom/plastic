# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

module Plastic
  class CLI
    module Commands
      class InstallerVerb < Command
        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          unknown = arguments.grep(/\A-/) - self.class::FLAGS
          raise Usage, "#{unknown.first} is not a flag of this command" unless unknown.empty?

          status = legacy.run(self.class::SCRIPT, *arguments)
          raise Failure, "#{self.class::SCRIPT} exited #{status}" unless status.zero?

          @output.next_step(self.class::AFTER, because: self.class::BECAUSE)
        end

        private

        def options
          @options ||= {}
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
