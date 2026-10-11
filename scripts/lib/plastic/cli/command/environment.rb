# frozen_string_literal: true

require_relative "../../harnesses/processes"
require_relative "../../harnesses/innermost"

module Plastic
  class CLI
    class Command
      # Where a call runs: the variables, the three streams, the home, the
      # working directory and the processes above it. A test passes its own;
      # bin/plastic passes the process's.
      Environment = Data.define(:env, :input, :out, :err, :home, :directory, :processes)

      # How a call's environment names its session.
      class Environment
        PLASTIC_SESSION = "PLASTIC_SESSION"

        def self.current
          new(env: ENV, input: $stdin, out: $stdout, err: $stderr, home: Dir.home, directory: Dir.pwd, processes: Harnesses::Processes.current)
        end

        def initialize(processes: Harnesses::Processes.none, **) = super

        # PLASTIC_SESSION when it is set, else the session of the innermost
        # harness; nil when none is set.
        def session
          named = env[PLASTIC_SESSION].to_s.strip
          named.empty? ? Harnesses::Innermost.new(env:, processes:, plastic_home:).session : named
        end

        def plastic_home = env["PLASTIC_HOME"] || File.join(home, ".plastic")
      end
    end
  end
end
