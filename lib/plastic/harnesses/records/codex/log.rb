# frozen_string_literal: true

module Plastic
  module Harnesses
    module Records
      class Codex
        # The lines of one Codex session log, the session and the window of one run. A line with no readable time is in no window.
        class Log
          KEYS = %w[input_tokens cached_input_tokens cache_write_input_tokens output_tokens].freeze

          # The figures of the last `token_count` line among `entries`, zero for each one it does not hold.
          def self.total(entries)
            usage = entries.reverse.filter_map { |entry| entry.dig("payload", "info", "total_token_usage") if entry.dig("payload", "type") == "token_count" }.first
            KEYS.map { |key| usage.is_a?(Hash) ? usage[key].to_i : 0 }
          end

          def initialize(entries, session, window)
            @timed = entries.map { |entry| Jsonl.time(entry) }.zip(entries).reject { |at, _| at.nil? }
            @session = session
            @window = window
          end

          def usage
            before = Log.total(@timed.filter_map { |at, entry| entry if at < @window.begin })
            final = Log.total(entries_through)
            return TokenUsage.none("no turn inside the run in the Codex session log of session #{@session}", worker_session: @session) if final == before

            figures(final.zip(before).map { |now, then_| now - then_ })
          end

          private

          def entries_through = @timed.filter_map { |at, entry| entry if at <= @window.end }

          def figures(growth)
            input, cached, written, output = growth
            TokenUsage.new(worker_session: @session, model: model, input_tokens: input - cached, output_tokens: output, cache_read_tokens: cached,
              cache_write_tokens: written, cost_usd: nil, note: "cost not found: the Codex session log holds none")
          end

          def model = entries_through.reverse.find { |entry| entry["type"] == "turn_context" }&.dig("payload", "model")
        end
      end
    end
  end
end
