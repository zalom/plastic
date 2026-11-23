# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One claim of a node, from the moment a session took it until its result.
      # `number` counts the runs of the node; an open run has no `ended_at`.
      # `harness` names the harness of the claiming session. `worker_session`, `model`, the four token counts and `cost_usd`
      # come from the harness's own record when the run ends; a figure it did not hold is nil, and `usage_note` says what was not found.
      Run = Data.define(:intent_id, :node_id, :number, :agent, :session_id, :started_at, :ended_at, :result, :origin_id,
        :harness, :worker_session, :usage_note, :model, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :cost_usd) do
        include Record

        def open? = ended_at.nil?
      end
    end
  end
end
