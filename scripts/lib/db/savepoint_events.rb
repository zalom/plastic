# encoding: UTF-8
# frozen_string_literal: true

require "json"
require_relative "../db"

module Plastic
  module DB
    # SavepointEvents: the savepoint_events append-only ledger (D5), plus the
    # JSONL export/rebuild pair that makes it durable across a lost DB
    # (intent 41, ACTION_5). Per-intent savepoint.md retires from the live
    # flow; this is its authoritative successor. ACTION_11 wires the gate
    # hooks onto stamp/export; this file only builds the primitives.
    #
    # savepoint_events.intent_id is an INTEGER FK to intents(id) (the
    # surrogate mirror row), while every other intent_id column in the
    # schema (lock_leases, roadmap_entries, sessions.active_intent_id) is the
    # human TEXT id. To keep this module's public API consistent with the
    # rest of Plastic::DB (every verb takes the human id, e.g. "41"),
    # `stamp`/`export`/`rebuild_from_export` accept the human id and resolve
    # the surrogate internally via a plain read against `intents`. A missing
    # `intents` row (the mirror has not synced this intent yet) is dormancy,
    # not an error: stamp/export fail open (no row/file written, no raise),
    # the same posture as an absent lease.
    #
    # Touches only its own table for normal operation (stamp/export never
    # write intents/roadmap_entries, only read them, exactly as the export's
    # trailing state record requires). rebuild_from_export is the one named
    # exception: it is the durable-recovery path, and restoring the
    # DB-authoritative operational fields (status/quadrant/queue/batch) onto
    # intents/roadmap_entries is the entire point of closing Q5, so it alone
    # writes there too.
    module SavepointEvents
      module_function

      # The (stage, event_type) pairs that are gate boundaries: landing a
      # lifecycle artifact, or the terminal disposition. Mirrors bridge.rb's
      # SAVEPOINT_MILESTONES set exactly, so ACTION_11's cutover reuses this
      # as its export trigger and its dedup key. Free-form events (anything
      # not in this set) are never deduped: only a gate milestone must be
      # once-only per (intent_id, stage, event_type).
      GATE_MILESTONES = [
        %w[Why spec.md\ created],
        %w[How plan.md\ created],
        %w[How checklist.md\ created],
        %w[Exec outcome.md\ created],
        %w[Done delivered],
        %w[Done abandoned],
      ].freeze

      def is_gate_milestone?(stage, event_type)
        GATE_MILESTONES.include?([stage, event_type])
      end

      # Append one row (fail-open: nil conn, or no matching `intents` row for
      # intent_id, both return false/nil and never raise). A gate-milestone
      # (stage, event_type) pair is written once only (D5's dedup); a
      # free-form event is written every time it is stamped.
      def stamp(conn, intent_id:, stage:, event_type:, actor_session:, occurred_at:, payload: {})
        return nil if conn.nil?

        Plastic::DB.with_write(conn) do |c|
          row_id = intent_row_id(c, intent_id)
          next false if row_id.nil?

          if is_gate_milestone?(stage, event_type) &&
             !milestone_rows(c, row_id, stage, event_type).empty?
            next false
          end

          c.execute(
            "INSERT INTO savepoint_events " \
            "(intent_id, stage, event_type, actor_session, payload, occurred_at, created_at, updated_at) " \
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [row_id, stage, event_type, actor_session, JSON.generate(payload), occurred_at, occurred_at, occurred_at]
          )
          true
        end
      end

      # Write <intent_dir>/savepoint.jsonl: one line per savepoint_events row
      # for intent_id (occurred_at then id order), followed by one trailing
      # {"kind":"state",...} record carrying status/quadrant (read from
      # intents) and queue/batch (read from roadmap_entries/roadmaps) -- the
      # record that closes the Q5 rebuild gap. Fail-open: a nil conn or a
      # missing intents row writes nothing and returns nil.
      def export(conn, intent_id:, intent_dir:)
        return nil if conn.nil?

        intent_row = conn.execute("SELECT id, status, quadrant FROM intents WHERE intent_id = ?", [intent_id]).first
        return nil if intent_row.nil?

        row_id, status, quadrant = intent_row
        queue, batch = queue_and_batch(conn, intent_id)

        lines = event_rows(conn, row_id).map { |row| event_line(row) }
        lines << state_line(status: status, quadrant: quadrant, queue: queue, batch: batch)

        path = File.join(intent_dir, "savepoint.jsonl")
        File.write(path, lines.map { |line| "#{line}\n" }.join)
        path
      end

      # Read savepoint.jsonl back: reinsert each event row verbatim, and
      # restore the trailing state record onto intents (status/quadrant) and
      # roadmap_entries/roadmaps (queue/batch) -- the durable-recovery path.
      # Fail-open: nil conn or a missing/empty export file is a no-op.
      def rebuild_from_export(conn, intent_id:, intent_dir:)
        return nil if conn.nil?

        path = File.join(intent_dir, "savepoint.jsonl")
        return nil unless File.exist?(path)

        lines = File.readlines(path).reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
        return nil if lines.empty?

        event_lines = lines.select { |line| line["kind"] == "event" }
        state = lines.find { |line| line["kind"] == "state" }
        restore_at = event_lines.map { |line| line["occurred_at"] }.min || state&.fetch("occurred_at", nil)

        Plastic::DB.with_write(conn) do |c|
          row_id = restore_intent_row(c, intent_id, state, restore_at)

          event_lines.each do |line|
            c.execute(
              "INSERT INTO savepoint_events " \
              "(intent_id, stage, event_type, actor_session, payload, occurred_at, created_at, updated_at) " \
              "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              [row_id, line["stage"], line["event_type"], line["actor_session"],
               JSON.generate(line["payload"] || {}), line["occurred_at"], line["occurred_at"], line["occurred_at"]]
            )
          end

          restore_roadmap_entry(c, intent_id, state, restore_at) if state && state["queue"]

          true
        end
      end

      # --- internals -----------------------------------------------------

      def intent_row_id(conn, intent_id)
        conn.execute("SELECT id FROM intents WHERE intent_id = ?", [intent_id]).dig(0, 0)
      end

      def milestone_rows(conn, row_id, stage, event_type)
        conn.execute(
          "SELECT id FROM savepoint_events WHERE intent_id = ? AND stage = ? AND event_type = ?",
          [row_id, stage, event_type]
        )
      end

      def event_rows(conn, row_id)
        conn.execute(
          "SELECT stage, event_type, actor_session, payload, occurred_at FROM savepoint_events " \
          "WHERE intent_id = ? ORDER BY occurred_at ASC, id ASC",
          [row_id]
        )
      end

      def event_line(row)
        stage, event_type, actor_session, payload, occurred_at = row
        JSON.generate(
          "kind" => "event",
          "stage" => stage,
          "event_type" => event_type,
          "actor_session" => actor_session,
          "payload" => JSON.parse(payload.nil? || payload.empty? ? "{}" : payload),
          "occurred_at" => occurred_at
        )
      end

      def state_line(status:, quadrant:, queue:, batch:)
        JSON.generate(
          "kind" => "state",
          "status" => status,
          "quadrant" => quadrant,
          "queue" => queue,
          "batch" => batch
        )
      end

      def queue_and_batch(conn, intent_id)
        row = conn.execute(
          "SELECT roadmaps.slug, roadmap_entries.batch_number FROM roadmap_entries " \
          "JOIN roadmaps ON roadmap_entries.roadmap_id = roadmaps.id " \
          "WHERE roadmap_entries.intent_id = ?",
          [intent_id]
        ).first
        row ? [row[0], row[1]] : [nil, nil]
      end

      # Upsert the intents row's authoritative-only fields (status/quadrant)
      # from the state record, creating a minimal row if the mirror hasn't
      # (re)built one yet. Timestamps are content-derived (the earliest
      # restored occurred_at), never Time.now, keeping rebuild deterministic.
      def restore_intent_row(conn, intent_id, state, restore_at)
        status = state && state["status"]
        quadrant = state && state["quadrant"]
        existing_id = intent_row_id(conn, intent_id)

        if existing_id
          conn.execute(
            "UPDATE intents SET status = ?, quadrant = ?, updated_at = ? WHERE id = ?",
            [status, quadrant, restore_at, existing_id]
          )
          existing_id
        else
          conn.execute(
            "INSERT INTO intents (intent_id, status, quadrant, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            [intent_id, status, quadrant, restore_at, restore_at]
          )
          intent_row_id(conn, intent_id)
        end
      end

      def restore_roadmap_entry(conn, intent_id, state, restore_at)
        slug = state["queue"]
        batch_number = state["batch"]

        roadmap_id = conn.execute("SELECT id FROM roadmaps WHERE slug = ?", [slug]).dig(0, 0)
        if roadmap_id.nil?
          conn.execute(
            "INSERT INTO roadmaps (slug, title, goal, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            [slug, slug, nil, restore_at, restore_at]
          )
          roadmap_id = conn.execute("SELECT id FROM roadmaps WHERE slug = ?", [slug]).dig(0, 0)
        end

        entry_id = conn.execute(
          "SELECT id FROM roadmap_entries WHERE roadmap_id = ? AND intent_id = ?",
          [roadmap_id, intent_id]
        ).dig(0, 0)

        if entry_id
          conn.execute(
            "UPDATE roadmap_entries SET batch_number = ?, updated_at = ? WHERE id = ?",
            [batch_number, restore_at, entry_id]
          )
        else
          conn.execute(
            "INSERT INTO roadmap_entries " \
            "(roadmap_id, intent_id, batch_number, status, position, created_at, updated_at) " \
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            [roadmap_id, intent_id, batch_number, nil, nil, restore_at, restore_at]
          )
        end
      end
    end
  end
end
