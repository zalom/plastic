# frozen_string_literal: true

require_relative "../../harnesses/processes"
require_relative "../../harnesses/innermost"

module Plastic
  class CLI
    class Command
      # Where a call runs: the variables, the three streams, the home, the
      # working directory, the processes above it and the clock. A test passes its own;
      # exe/plastic passes the process's.
      Environment = Data.define(:env, :input, :out, :err, :home, :directory, :processes, :clock)

      # How a call's environment names its session.
      class Environment
        PLASTIC_SESSION = "PLASTIC_SESSION"

        def self.current
          new(env: ENV, input: $stdin, out: $stdout, err: $stderr, home: Dir.home, directory: Dir.pwd, processes: Harnesses::Processes.current, clock: Time)
        end

        def initialize(processes: Harnesses::Processes.none, clock: Time, **) = super

        def now = clock.now

        # PLASTIC_SESSION when it is set, else the session of the innermost
        # harness, else `terminal-` and the login of a person at a terminal; nil when none of these is known.
        def session
          named = env[PLASTIC_SESSION].to_s.strip
          return named unless named.empty?

          Harnesses::Innermost.new(env:, processes:, plastic_home:).session || terminal_session
        end

        # The harness whose session variable names the session of the call, or an empty text when none does (PLASTIC_SESSION alone, a terminal).
        def harness_name = Harnesses.sessions(env).find { |_name, id| id == session }&.first.to_s

        # The harness name and the home its records are read from, as the last two fields of a Context::Harness.
        def harness_record = [harness_name, home]

        def terminal_session
          login = (env["USER"] || env["LOGNAME"]).to_s.strip
          login.empty? ? nil : "terminal-#{login}"
        end

        def plastic_home = env["PLASTIC_HOME"] || File.join(home, ".plastic")
      end
    end
  end
end
