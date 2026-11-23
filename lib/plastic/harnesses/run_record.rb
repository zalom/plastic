# frozen_string_literal: true

require_relative "token_usage"
require_relative "records/claude"
require_relative "records/codex"

module Plastic
  module Harnesses
    # What the local record of a harness holds of one node run: the worker's session, the model, the tokens and the cost.
    # It reads files the harness wrote and starts nothing. Whatever the record lacks is nil and named in the note; it never raises.
    # Claude Code and Codex are read. Docs: docs/usage/node-lifecycle.md.
    class RunRecord
      def initialize(home:)
        @readers = { "claude-code" => Records::Claude.new(home:), "codex" => Records::Codex.new(home:) }.freeze
      end

      # The usage of the run of `harness` session `session` from `from` to `to`, claimed with `claim`, such as "485 n2".
      def read(harness:, session:, from:, to:, claim:)
        reader = @readers[harness.to_s]
        return TokenUsage.none(missing(harness)) unless reader

        reader.read(session:, from:, to:, claim:)
      rescue StandardError => error
        TokenUsage.none("the #{harness} record could not be read: #{error.message}")
      end

      private

      def missing(harness) = harness.to_s.empty? ? "no harness record: the claim named no harness" : "no harness record: Plastic reads none for #{harness}"
    end
  end
end
