# frozen_string_literal: true

module Plastic
  module Harnesses
    module Records
      class Claude
        # The lines of one Claude Code transcript and the window of one run. A turn is an assistant line with `message.usage`,
        # written again for each content block of one message, so the last line of a message id counts. The cost is the growth of
        # the `cost-state` total over the run, and it is known only when a `cost-state` comes after the last turn of the run:
        # Claude Code writes one about once per session, at its stop, so a run in a live session has none.
        class Transcript
          COUNTS = %w[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens].freeze

          def self.turn?(entry) = entry["type"] == "assistant" && entry.dig("message", "usage").is_a?(Hash) && !Jsonl.time(entry).nil?

          def self.commands(entry)
            Array(entry.dig("message", "content")).grep(Hash).select { |part| part["type"] == "tool_use" }.filter_map { |part| part.dig("input", "command") }
          end

          # The total of the last `cost-state` line among `entries`, nil when there is none.
          def self.total(entries) = entries.reverse.find { |entry| entry["type"] == "cost-state" }&.fetch("totalCostUSD", nil)

          def initialize(entries, window)
            @entries = entries
            @window = window
          end

          def usage(name)
            return TokenUsage.none("no turn inside the run in the Claude Code transcript of session #{name}", worker_session: name) if windowed.empty?

            figures(name, cost)
          end

          private

          def figures(name, cost)
            input, output, cache_read, cache_write = COUNTS.map { |key| sum(key) }
            TokenUsage.new(worker_session: name, model: turns.last.dig("message", "model"), input_tokens: input, output_tokens: output,
              cache_read_tokens: cache_read, cache_write_tokens: cache_write, cost_usd: cost, note: cost ? "" : "cost not found: the Claude Code transcript holds no cost after the run")
          end

          def sum(key) = turns.sum { |turn| turn.dig("message", "usage", key).to_i }

          def windowed = @windowed ||= @entries.select { |entry| self.class.turn?(entry) && @window.cover?(Jsonl.time(entry)) }

          def turns = @turns ||= windowed.reverse.uniq { |entry| entry.dig("message", "id") }.reverse

          # The last `cost-state` between the last turn of the run and the first turn after it, less the last one before the run.
          def cost
            closing = Transcript.total(@entries[position(windowed.last)...(first_after || @entries.size)])
            closing && (closing - (Transcript.total(@entries.first(position(windowed.first))) || 0.0))
          end

          def position(entry) = @entries.index { |candidate| candidate.equal?(entry) }

          def first_after = @entries.index { |entry| self.class.turn?(entry) && Jsonl.time(entry) > @window.end }
        end
      end
    end
  end
end
