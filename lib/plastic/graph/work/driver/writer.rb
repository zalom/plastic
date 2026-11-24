# frozen_string_literal: true

require "time"
require_relative "../../rows/node"
require_relative "../../sql"

module Plastic
  module Graph
    module Work
      module Driver
        # The row of a claim held by a session, with whether it lapsed and whether its session ended.
        Held = Data.define(:session, :last_seen, :lapsed, :ended) do
          def self.from(row, now:, ended:)
            seen = Time.parse([row["seen_at"], row["claimed_at"]].find { |stamp| !stamp.to_s.empty? } || "1970-01-01T00:00:00Z")
            new(session: row["session_id"], last_seen: seen, lapsed: seen < now - Node::LAPSE, ended:)
          end

          # Another session's claim that is live: not lapsed and its session not ended.
          def standing_for?(by) = live? && other?(by)

          def live? = !lapsed && !ended

          def other?(by) = session != by

          def problem(intent_id)
            "intent #{intent_id} is driven by session #{session}, last seen #{Plastic.local(last_seen)}; " \
              "its claim lapses 15 minutes after its last renewal or when its session ends"
          end

          def free_reason = lapsed ? "the claim lapsed" : "the session ended"
        end

        # A change of driver as a work log line: nil when the same session drives again.
        Handover = Data.define(:by, :held, :take_over) do
          def text
            return "Driver #{by}" if held.nil?

            old = held.session
            "Driver #{by} took over from #{old}: #{held.standing_for?(by) ? take_over : held.free_reason}" unless old == by
          end
        end

        # The driver claim of an intent: the one session that acts on it. It works like the claim of a node: it lapses
        # after the same 15 minutes without a renewal, it is released when its session ends, and a session that finds
        # it lapsed or its session ended takes it. A live claim of another session is taken only with a reason, which
        # is the owner's word. The write is guarded by the holder it read, so two sessions cannot both win.
        class Writer
          TAKE_SQL = <<~SQL
            INSERT INTO drivers (intent_id, origin_id, session_id, claimed_at, seen_at)
            VALUES (:intent_id, :origin, :by, :now, :now)
            ON CONFLICT (intent_id, origin_id) DO UPDATE SET session_id = :by, claimed_at = :now, seen_at = :now
            WHERE session_id IS :holder
            RETURNING session_id
          SQL

          RENEW_SQL = "UPDATE drivers SET seen_at = :now WHERE session_id = :session AND origin_id = :origin"
          RELEASE_SQL = "DELETE FROM drivers WHERE session_id = :session AND origin_id = :origin"
          RELEASE_INTENT_SQL = "DELETE FROM drivers WHERE intent_id = :intent_id AND origin_id = :origin"
          HOLDER_SQL = "SELECT session_id, claimed_at, seen_at FROM drivers WHERE intent_id = :intent_id AND origin_id = :origin"

          def initialize(databases, retrieval, clock: Time)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # Why `session` may not drive the intent, or nil when it may: another session holds a live claim.
          def problem(intent_id, session)
            [holder(intent_id)].compact.find { |held| held.standing_for?(session) }&.problem(intent_id)
          end

          # [:driving, holder, line], [:took_over, holder, line] or [:held, holder, nil]. The line is the work log text of a
          # change of driver, nil when the same session drives again.
          def claim(intent_id:, by:, take_over: nil)
            held = holder(intent_id)
            standing = held&.standing_for?(by)
            return [:held, held.session, nil] if standing && take_over.to_s.empty?
            return [:held, current_session(intent_id), nil] unless write(intent_id, by, held&.session)

            [standing ? :took_over : :driving, held&.session, Handover.new(by:, held:, take_over:).text]
          end

          # Whether a live claim holds the intent, whichever session holds it.
          def held?(intent_id) = holder(intent_id)&.live? || false

          def renew(session) = write_for(RENEW_SQL, session)

          def release(session) = write_for(RELEASE_SQL, session)

          # Deletes the claim of the intent, whoever holds it. Returns the session that held it, or nil when no claim stood.
          def release_intent(intent_id)
            held = holder(intent_id)&.session
            @databases.fetch(:store).transaction { |batch| batch.add(RELEASE_INTENT_SQL, intent_id:, origin: @retrieval.origin_id) } if held
            held
          end

          private

          def holder(intent_id)
            row = @databases.fetch(:store).row(HOLDER_SQL, intent_id:, origin: @retrieval.origin_id)
            row && Held.from(row, now: @clock.now, ended: ended?(row["session_id"]))
          end

          def current_session(intent_id) = holder(intent_id).session

          def write(intent_id, by, holder)
            bind = { intent_id:, origin: @retrieval.origin_id, by:, holder:, now: Plastic.timestamp(@clock.now) }
            @databases.fetch(:store).transaction { |batch| batch.write(:drivers, TAKE_SQL, **bind) }.any?
          end

          def write_for(sql, session)
            @databases.fetch(:store).transaction do |batch|
              batch.add(sql, session:, origin: @retrieval.origin_id, now: Plastic.timestamp(@clock.now))
            end
          end

          def ended?(session)
            sql = "SELECT 1 FROM sessions WHERE session_id = :session AND ended_at IS NOT NULL AND ended_at != ''"
            !@databases.fetch(:local).row(sql, session:).nil?
          end
        end
      end
    end
  end
end
