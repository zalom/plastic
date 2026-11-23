# frozen_string_literal: true

require_relative "../token_usage"
require_relative "jsonl"

module Plastic
  module Harnesses
    module Records
      # Reads one node run from Claude Code's local transcripts, `projects/*/SESSION.jsonl`. A turn is an assistant line with
      # `message.usage`, written again for each content block of one message, so the last line of a message id counts. The cost
      # is the growth of the `cost-state` total over the run. A subagent that ran the claim command inside the run is the
      # worker: its own file, `SESSION/subagents/agent-ID.jsonl`, holds the usage. Docs: docs/usage/node-lifecycle.md.
      class Claude
        def initialize(home:)
          @home = home
        end

        # The usage of the run from `from` to `to`, claimed with `claim` (the intent id and node id), by `session`.
        def read(session:, from:, to:, claim:)
          path = Dir.glob(File.join(@home, ".claude", "projects", "*", "#{session}.jsonl")).min
          return TokenUsage.none("no Claude Code transcript for session #{session}") unless path

          worker = subagent(path, session, from..to, claim) || path
          usage(worker, File.basename(worker, ".jsonl"), from..to)
        end

        private

        def usage(path, name, window)
          entries = Jsonl.read(path)
          return TokenUsage.none("the Claude Code transcript of session #{name} is unreadable", worker_session: name) unless entries

          turns = turns(entries, window)
          return TokenUsage.none("no turn inside the run in the Claude Code transcript of session #{name}", worker_session: name) if turns.empty?

          totals(turns, name, cost(entries, window))
        end

        def totals(turns, name, cost)
          sums = %w[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens].map { |key| turns.sum { |turn| turn.dig("message", "usage", key).to_i } }
          TokenUsage.new(worker_session: name, model: turns.last.dig("message", "model"), input_tokens: sums[0], output_tokens: sums[1],
            cache_read_tokens: sums[2], cache_write_tokens: sums[3], cost_usd: cost, note: cost ? "" : "cost not found in the Claude Code transcript")
        end

        def turns(entries, window)
          entries.select { |entry| turn?(entry) && window.cover?(Jsonl.time(entry)) }.reverse.uniq { |entry| entry.dig("message", "id") }.reverse
        end

        def turn?(entry) = entry["type"] == "assistant" && entry.dig("message", "usage").is_a?(Hash) && !Jsonl.time(entry).nil?

        # The total grew from the last `cost-state` before the first turn of the run to the last one before the first turn after it.
        def cost(entries, window)
          after = last_cost(entries, turn_at(entries) { |at| at > window.end })
          after && (after - (last_cost(entries, turn_at(entries) { |at| at >= window.begin }) || 0.0))
        end

        def turn_at(entries) = entries.index { |entry| turn?(entry) && yield(Jsonl.time(entry)) }

        def last_cost(entries, index) = entries.first(index || entries.size).reverse.find { |entry| entry["type"] == "cost-state" }&.fetch("totalCostUSD", nil)

        def subagent(path, session, window, claim)
          pattern = /node claim #{Regexp.escape(claim)}(\s|\z)/
          Dir.glob(File.join(File.dirname(path), session, "subagents", "agent-*.jsonl")).sort.find { |file| claimed?(file, window, pattern) }
        end

        def claimed?(file, window, pattern)
          entries = Jsonl.read(file) or return false
          entries.any? { |entry| turn?(entry) && window.cover?(Jsonl.time(entry)) && commands(entry).any? { |command| command.match?(pattern) } }
        end

        def commands(entry)
          Array(entry.dig("message", "content")).filter_map { |block| block.dig("input", "command") if block.is_a?(Hash) && block["type"] == "tool_use" }
        end
      end
    end
  end
end
