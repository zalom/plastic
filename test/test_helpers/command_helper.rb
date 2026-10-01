# frozen_string_literal: true

require "stringio"

module Plastic
  class TestCase
    # One call of the kernel command line, against the test's home.
    module CommandHelper
      Result = Data.define(:out, :err, :code)

      def environment(env: {}, input: "", out: StringIO.new, err: StringIO.new)
        Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }.merge(env),
          input: StringIO.new(input), out:, err:, home: @home, directory: @home)
      end

      def plastic(*argv, env: {}, input: "", table: Fixtures::TABLE)
        out = StringIO.new
        err = StringIO.new
        code = Plastic::CLI.call(argv, environment: environment(env:, input:, out:, err:), table:)
        Result.new(out.string, err.string, code)
      end

      def routine_run(tool, subject)
        Plastic::Graph.open(home: @plastic_home, store: "global").retrieval.routine_run(tool, subject)
      end
    end
  end
end
