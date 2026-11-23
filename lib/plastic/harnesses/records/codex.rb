# frozen_string_literal: true

require_relative "../token_usage"
require_relative "jsonl"
require_relative "codex/log"

module Plastic
  module Harnesses
    module Records
      # Reads one node run from Codex's local session log, `sessions/YYYY/MM/DD/rollout-TIME-SESSION.jsonl`. The log keeps a
      # running total of tokens, so the run's tokens are the growth of the total from before the run to its end. The model is
      # the one of the last `turn_context` at the end of the run. The log holds no cost. The reading of the log is in Codex::Log.
      class Codex
        def initialize(home:)
          @home = home
        end

        # Codex has no subagent to look for, so it takes the claim of the other readers and ignores it.
        def read(session:, from:, to:, **_claim)
          path = Dir.glob(File.join(@home, ".codex", "sessions", "*", "*", "*", "rollout-*-#{session}.jsonl")).min
          return TokenUsage.none("no Codex session log for session #{session}") unless path

          entries = Jsonl.read(path)
          entries ? Log.new(entries, session, from..to).usage : TokenUsage.none("the Codex session log of session #{session} is unreadable", worker_session: session)
        end
      end
    end
  end
end
