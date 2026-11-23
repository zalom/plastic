# frozen_string_literal: true

require_relative "../token_usage"
require_relative "jsonl"

module Plastic
  module Harnesses
    module Records
      # Reads one node run from Codex's local session log, `sessions/YYYY/MM/DD/rollout-TIME-SESSION.jsonl`. The log keeps a
      # running total of tokens, so the run's tokens are the growth of the total from before the run to its end. The model is
      # the one of the last `turn_context` at the end of the run. The log holds no cost.
      class Codex
        KEYS = %w[input_tokens cached_input_tokens cache_write_input_tokens output_tokens].freeze

        def initialize(home:)
          @home = home
        end

        def read(session:, from:, to:, claim: nil)
          path = Dir.glob(File.join(@home, ".codex", "sessions", "*", "*", "*", "rollout-*-#{session}.jsonl")).min
          return TokenUsage.none("no Codex session log for session #{session}") unless path

          entries = Jsonl.read(path)
          return TokenUsage.none("the Codex session log of session #{session} is unreadable", worker_session: session) unless entries

          usage(entries, session, from, to)
        end

        private

        def usage(entries, session, from, to)
          before = total(entries.select { |entry| (Jsonl.time(entry) || from) < from })
          final = total(entries.select { |entry| (Jsonl.time(entry) || to + 1) <= to })
          return TokenUsage.none("no turn inside the run in the Codex session log of session #{session}", worker_session: session) if final == before

          growth = KEYS.zip(final.zip(before)).to_h { |key, (now, then_)| [key, now - then_] }
          figures(growth, model(entries, to), session)
        end

        def figures(growth, model, session)
          TokenUsage.new(worker_session: session, model:, input_tokens: growth["input_tokens"] - growth["cached_input_tokens"], output_tokens: growth["output_tokens"],
            cache_read_tokens: growth["cached_input_tokens"], cache_write_tokens: growth["cache_write_input_tokens"], cost_usd: nil,
            note: "cost not found: the Codex session log holds none")
        end

        def total(entries)
          usage = entries.reverse.filter_map { |entry| entry.dig("payload", "info", "total_token_usage") if entry.dig("payload", "type") == "token_count" }.first
          KEYS.map { |key| usage.is_a?(Hash) ? usage[key].to_i : 0 }
        end

        def model(entries, to)
          entries.reverse.find { |entry| entry["type"] == "turn_context" && (Jsonl.time(entry) || to) <= to }&.dig("payload", "model")
        end
      end
    end
  end
end
