# encoding: UTF-8
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
