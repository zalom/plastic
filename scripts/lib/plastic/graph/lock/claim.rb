# frozen_string_literal: true

require "time"

module Plastic
  module Graph
    class Lock
      # A node of the lock's intent that the lock's session holds claimed,
      # and when it claimed it.
      Claim = Data.define(:id, :claimed_at) do
        # Claimed for no longer than the node limit at `now`.
        def open?(now) = (now - Time.parse(claimed_at)) <= NODE_LIMIT
      end
    end
  end
end
