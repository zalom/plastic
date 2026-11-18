# frozen_string_literal: true

require_relative "../session"

module Plastic
  module Graph
    module Work
      class Session
        # The write side of the home's `sessions` table for one
        # store. A put names only the columns it sets, so a write keeps the rest.
        class Writer
          def initialize(home, store:, clock:)
            @home = home
            @store = store
            @clock = clock
          end

          # Upserts the session row, keeping `started_at` once it is set, and clears an end: a session that opens again is live.
          def open_session(session_id, harness:, directory:)
            opened({ session_id:, harness:, store: @store, directory:, ended_at: nil, end_reason: nil })
          end

          # Opens the session row, keeping its harness, then sets its last
          # turn to now.
          def stamp_turn(session_id, directory:)
            opened({ session_id:, store: @store, directory: })
            put(:sessions, { session_id:, last_turn_at: Plastic.timestamp(@clock.now) })
          end

          # The session ended: its time and reason, nothing else.
          def end_session(session_id, reason:) = put(:sessions, { session_id:, ended_at: Plastic.timestamp(@clock.now), end_reason: reason })

          # The one prose line of a session; a session with no row gets one.
          def write_note(session_id, text) = put(:sessions, { session_id:, note: text })

          private

          def opened(row) = put(:sessions, started?(row[:session_id]) ? row : row.merge(started_at: Plastic.timestamp(@clock.now)))

          def started?(session_id)
            @home.rows("SELECT 1 FROM sessions WHERE session_id = :session_id AND started_at IS NOT NULL", session_id:).any?
          end

          def put(table, row) = @home.transaction { |batch| batch.put(table, row) }
        end
      end
    end
  end
end
