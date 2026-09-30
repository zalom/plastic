# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # Where a call runs: the variables, the three streams, the home and the
      # working directory. A test passes its own; bin/plastic passes the
      # process's.
      Environment = Data.define(:env, :input, :out, :err, :home, :directory)

      # How a call's environment names its session.
      class Environment
        # The first of these that is set names the calling session. Claude
        # Code sets the second; any harness may set the first.
        SESSION_VARIABLES = %w[PLASTIC_SESSION CLAUDE_CODE_SESSION_ID].freeze

        def self.current = new(env: ENV, input: $stdin, out: $stdout, err: $stderr, home: Dir.home, directory: Dir.pwd)

        # The harness session that made the call, or nil when none is set.
        def session = SESSION_VARIABLES.map { |variable| env[variable] }.find { |value| !value.to_s.strip.empty? }
      end
    end
  end
end
