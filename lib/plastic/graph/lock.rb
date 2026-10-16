# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # One row of the home's `locks` table: the session that holds the
    # delivery lock of one intent of one store.
    Lock = Data.define(:store, :intent_id, :session_id, :mode, :taken_at, :renewed_at) do
      include Record
    end

    class Lock
      TTL = 1800
      NODE_LIMIT = 7200
      WINDOW = "#{TTL / 60} minutes".freeze
    end
  end
end

require_relative "lock/claim"
require_relative "lock/liveness"
