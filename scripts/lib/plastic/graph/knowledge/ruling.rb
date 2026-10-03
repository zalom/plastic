# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # An owner decision, numbered D1, D2 and on within its intent. The owner
      # speaks it in chat; the agent writes it with `plastic intent rule`.
      Ruling = Data.define(:intent_id, :id, :text, :supersedes, :at, :session_id, :origin_id) do
        include Record

        def ref = "#{intent_id}/#{id}"
      end
    end
  end
end
