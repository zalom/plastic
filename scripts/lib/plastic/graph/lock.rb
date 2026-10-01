# frozen_string_literal: true

require "time"
require_relative "record"

module Plastic
  module Graph
    # One row of the home's `locks` table: the session that holds the
    # delivery lock of one intent of one store.
    Lock = Data.define(:store, :intent_id, :session_id, :mode, :taken_at, :renewed_at) do
      include Record
    end

    # A lock's liveness: renewed within the TTL of now.
    class Lock
      TTL = 1800

      # True when `renewed_at` lies within the TTL of `now`.
      def live?(now = Time.now) = (now - Time.parse(renewed_at)) <= TTL
    end
  end
end
