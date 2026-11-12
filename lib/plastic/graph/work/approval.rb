# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # The owner's go-ahead for one intent: one row, written once.
      Approval = Data.define(:intent_id, :origin_id, :at, :session_id) do
        include Record
      end
    end
  end
end
