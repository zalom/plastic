# frozen_string_literal: true

require "time"
require_relative "../../rows/node"
require_relative "../../sql"

module Plastic
  module Graph
    module Work
      module Driver
        # The driver claim of an intent: the one session that acts on it. It works like the claim of a node: it lapses
        # after the same 15 minutes without a renewal, it is released when its session ends, and a session that finds
        # it lapsed or its session ended takes it. A live claim of another session is taken only with a reason, which
        # is the owner's word. The write is guarded by the holder it read, so two sessions cannot both win.
        class Writer
          LAPSE = Node::LAPSE

          TAKE_SQL = <<~SQL
            INSERT INTO drivers (intent_id, origin_id, session_id, claimed_at, seen_at)
            VALUES (:intent_id, :origin, :by, :now, :now)
            ON CONFLICT (intent_id, origin_id) DO UPDATE SET session_id = :by, claimed_at = :now, seen_at = :now
            WHERE session_id IS :holder
            RETURNING session_id
          SQL

          RENEW_SQL = "UPDATE drivers SET seen_at = :now WHERE session_id = :session AND origin_id = :origin"
          RELEASE_SQL = "DELETE FROM drivers WHERE session_id = :session AND origin_id = :origin"
          HOLDER_SQL = "SELECT session_id, claimed_at, seen_at FROM drivers WHERE intent_id = :intent_id AND origin_id = :origin"

          def initialize(databases, retrieval, clock: Time)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # Why `session` may not drive the intent, or nil when it may: another session holds a live claim.
          def problem(intent_id, session)
            held = holder(intent_id)
            return nil unless standing?(held, session)

            "intent #{intent_id} is driven by session #{held["session_id"]}, last seen #{Plastic.local(last_seen(held))}; " \
              "its claim lapses 15 minutes after its last renewal or when its session ends"
          end

          # [:driving, holder, line], [:took_over, holder, line] or [:held, holder, nil]. The line is the work log text of a
          # change of driver, nil when the same session drives again.
          def claim(intent_id:, by:, take_over: nil)
            held = holder(intent_id)
            old = held && held["session_id"]
            standing = standing?(held, by)
            return [:held, old, nil] if standing && take_over.to_s.empty?
            return [:held, holder(intent_id)&.fetch("session_id"), nil] unless write(intent_id, by, old)

            [standing ? :took_over : :driving, old, line(by, old, standing ? take_over : lapse_reason(held))]
          end

          def renew(session) = write_for(RENEW_SQL, session)

          def release(session) = write_for(RELEASE_SQL, session)

          private

          def holder(intent_id) = @databases.fetch(:store).row(HOLDER_SQL, intent_id:, origin: @retrieval.origin_id)

          def write(intent_id, by, holder)
            bind = { intent_id:, origin: @retrieval.origin_id, by:, holder:, now: Plastic.timestamp(@clock.now) }
            @databases.fetch(:store).transaction { |batch| batch.write(:drivers, TAKE_SQL, **bind) }.any?
          end

          def write_for(sql, session)
            @databases.fetch(:store).transaction do |batch|
              batch.add(sql, session:, origin: @retrieval.origin_id, now: Plastic.timestamp(@clock.now))
            end
          end

          # Another session's claim that is live.
          def standing?(held, by) = !held.nil? && held["session_id"] != by && live?(held)

          def lapse_reason(held) = held && lapsed?(held) ? "the claim lapsed" : "the session ended"

          def line(by, old, why)
            return "Driver #{by}" if old.nil?

            "Driver #{by} took over from #{old}: #{why}" unless old == by
          end

          def live?(held) = !lapsed?(held) && !ended?(held["session_id"])

          def lapsed?(held) = last_seen(held) < @clock.now - LAPSE

          def last_seen(held) = Time.parse([held["seen_at"], held["claimed_at"]].find { |stamp| !stamp.to_s.empty? } || "1970-01-01T00:00:00Z")

          def ended?(session)
            ended = @databases.fetch(:local).row("SELECT ended_at FROM sessions WHERE session_id = :session", session:)
            !ended.nil? && !ended["ended_at"].to_s.empty?
          end
        end
      end
    end
  end
end
