# frozen_string_literal: true

require "json"

module Plastic
  module TestHelpers
    # Short records in the formats the harnesses write, as lines of JSON. The shapes are copied from real
    # Claude Code transcripts (assistant lines with message.usage, cost-state lines, subagent files) and
    # real Codex session logs (turn_context and token_count events); only the numbers are small.
    module HarnessRecordFixtures
      def jsonl(*entries) = "#{entries.map { |entry| JSON.generate(entry) }.join("\n")}\n"

      def claude_turn(at, id:, model: "claude-sonnet-5-5", block: nil, **tokens)
        counts = { input: 2, output: 10, cache_read: 100, cache_write: 1000 }.merge(tokens)
        usage = { input_tokens: counts[:input], output_tokens: counts[:output], cache_read_input_tokens: counts[:cache_read], cache_creation_input_tokens: counts[:cache_write] }
        content = block ? [block] : []
        { type: "assistant", timestamp: at, sessionId: "s-1", message: { id:, model:, role: "assistant", usage:, content: } }
      end

      def claude_cost(total) = { type: "cost-state", sessionId: "s-1", totalCostUSD: total, modelUsage: {} }

      def claude_claim_call(at, text)
        claude_turn(at, id: "msg_claim", block: { type: "tool_use", name: "Bash", input: { command: text } })
      end

      def write_claude(session, text, project: "-work-app", under: nil)
        path = File.join(@home, ".claude", "projects", project, *under, "#{session}.jsonl")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
        path
      end

      def codex_context(at, model) = { timestamp: at, type: "turn_context", payload: { turn_id: "t", model: } }

      def codex_count(at, input:, cached:, output:, written: 0)
        total = { input_tokens: input, cached_input_tokens: cached, cache_write_input_tokens: written, output_tokens: output, total_tokens: input + output }
        { timestamp: at, type: "event_msg", payload: { type: "token_count", info: { total_token_usage: total } } }
      end

      def write_codex(session, text)
        path = File.join(@home, ".codex", "sessions", "2026", "11", "22", "rollout-2026-11-22T10-00-00-#{session}.jsonl")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
        path
      end
    end
  end
end
