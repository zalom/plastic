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

    class Lock
      TTL = 1800
      NODE_LIMIT = 7200
      WINDOW = "#{TTL / 60} minutes".freeze

      # A node of the lock's intent that the lock's session holds claimed,
      # and when it claimed it.
      Claim = Data.define(:id, :claimed_at) do
        # Claimed for no longer than the node limit at `now`.
        def open?(now) = (now - Time.parse(claimed_at)) <= NODE_LIMIT
      end

      # Whether a lock is live, and why. A lock of an ended session is never
      # live. Otherwise it is live while it was renewed within the TTL, or
      # while its session holds a node of the intent claimed for no longer
      # than the node limit.
      Liveness = Data.define(:lock, :ended_at, :claims) do
        def self.read(lock, local:, work:)
          new(lock, ended_at(lock, local), claims(lock, work))
        end

        def self.ended_at(lock, local)
          local.row("SELECT ended_at FROM sessions WHERE session_id = :session_id", session_id: lock.session_id)&.fetch("ended_at")
        end

        def self.claims(lock, work)
          return [] unless work

          work.rows(%(SELECT id, updated_at FROM nodes WHERE intent_id = :intent_id AND state = 'claimed' AND "by" = :session_id ORDER BY id),
            intent_id: lock.intent_id.to_s, session_id: lock.session_id).map { |row| Claim.new(*row.values_at("id", "updated_at")) }
        end

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
