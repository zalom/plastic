# frozen_string_literal: true

require "time"

module Plastic
  module Graph
    class Lock
      # Whether a lock is live, and why. A lock of an ended session is never
      # live. Otherwise it is live while it was renewed within the TTL, or
      # while its session holds a node of the intent claimed for no longer
      # than the node limit.
      Liveness = Data.define(:lock, :ended_at, :claims) do
        def live?(now = Time.now) = !ended? && (renewed?(now) || claims.any? { |claim| claim.open?(now) })

        # The reason in one phrase.
        def why(now = Time.now)
          return "session #{lock.session_id} ended #{ended_at}" if ended?
          return "renewed within #{WINDOW}" if renewed?(now)

          claim = open_claim(now)
          claim ? "node #{claim.id} open since #{claim.claimed_at}" : "no renewal within #{WINDOW} and no open node"
        end

        private

        def ended? = !ended_at.to_s.empty?

        def renewed?(now) = (now - Time.parse(lock.renewed_at)) <= TTL

        def open_claim(now) = claims.find { |claim| claim.open?(now) }
      end
    end
  end
end
