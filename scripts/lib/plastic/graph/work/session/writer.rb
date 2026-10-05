# frozen_string_literal: true

require_relative "../session"

module Plastic
  module Graph
    module Work
      class Session
        # The write side of the home's `sessions` and `locks` tables for one
        # store. A put names only the columns it sets, so a write keeps the rest.
        class Writer
          def initialize(home, store:)
            @home = home
            @store = store
          end

          # Upserts the session row, keeping `started_at` once it is set.
          def open_session(session_id, harness:, directory:)
            row = { session_id:, harness:, store: @store, directory: }
            put(:sessions, started?(session_id) ? row : row.merge(started_at: Plastic.now))
          end

          # Opens the session row, then sets its last turn to now.
          def stamp_turn(session_id, harness:, directory:)
            open_session(session_id, harness:, directory:)
            put(:sessions, { session_id:, last_turn_at: Plastic.now })
          end

          # The session ended: its time and reason, nothing else.
          def end_session(session_id, reason:) = put(:sessions, { session_id:, ended_at: Plastic.now, end_reason: reason })

          # The one prose line of a session; a session with no row gets one.
          def write_note(session_id, text) = put(:sessions, { session_id:, note: text })

          # Writes the lock row of this store, taken and renewed now.
          def take_lock(intent_id, session_id:, mode:)
            now = Plastic.now
            put(:locks, { store: @store, intent_id:, session_id:, mode:, taken_at: now, renewed_at: now })
          end

          # Renews every lock row this session names, live or lapsed, and
          # returns how many: the key is the store and the intent, so a lapsed
          # row still naming this session was taken by no one else (review A10).
          def renew_locks(session_id)
            found = @home.transaction do |batch|
              batch.add("UPDATE \"locks\" SET \"renewed_at\" = :now WHERE \"session_id\" = :session_id RETURNING session_id",
                now: Plastic.now, session_id:)
            end
            found.sum(&:size)
          end

          private

          def started?(session_id)
            @home.rows("SELECT 1 FROM sessions WHERE session_id = :session_id AND started_at IS NOT NULL", session_id:).any?
          end

          def put(table, row) = @home.transaction { |batch| batch.put(table, row) }
        end
      end
    end
  end
end
