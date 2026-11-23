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

        def lacks_cost? = !ended_at.nil? && cost_usd.nil?

        # The window of the run, `grace` seconds past the stored end.
        def window(grace) = Time.iso8601(started_at)..(Time.iso8601(ended_at) + grace)

        # What the harness record is asked for: the session of the claim and the run's window.
        def record_query(grace) = window(grace).then { |range| { harness:, session: session_id, from: range.begin, to: range.end } }

        # The command the claim turn of the run holds, such as "485 n2".
        def claim_text = "#{intent_id} #{node_id}"

        # The keys of the writer that fills the cost of this run.
        def cost_key = { intent_id:, id: node_id, number: }
      end
    end
  end
end
