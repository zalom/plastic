# frozen_string_literal: true

module Plastic
  module Harnesses
    # What a harness's own record held of one node run: the worker's own session, the model, the four token counts and the cost.
    # A figure the record did not hold is nil, and `note` says what was not found; it is empty when the record held everything.
    TokenUsage = Data.define(:worker_session, :model, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :cost_usd, :note) do
      # A run for which the record gave no figure, with the reason.
      def self.none(note, worker_session: nil)
        new(worker_session:, model: nil, input_tokens: nil, output_tokens: nil, cache_read_tokens: nil, cache_write_tokens: nil, cost_usd: nil, note:)
      end

      def found? = !input_tokens.nil?
    end
  end
end
