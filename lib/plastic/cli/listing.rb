# frozen_string_literal: true

module Plastic
  class CLI
    # The shipped commands, one row each, as lines or as one document with --json.
    class Listing
      def initialize(environment, table)
        @environment = environment
        @table = table
      end

      def call(argv)
        output = printer(argv)
        @table.each { |name, (_, summary)| output.row(name, summary) }
        output.flush
        Command::OK
      end

      private

      def printer(argv)
        (argv.include?("--json") ? JsonOutput : TextOutput).new(out: @environment.out, err: @environment.err)
      end
    end
  end
end
