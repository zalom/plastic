require "time"
require_relative "../db"
require_relative "mirror"
require_relative "savepoint_events"
require_relative "schema"

module Plastic
  module DB
    # Rebuild: proves the DB is disposable (intent 41, ACTION_8, AC3). A cold
    # `rebuild!` repopulates every derived + snapshot-restored table from
    # files-on-disk plus each intent's committed savepoint.jsonl, and
    # `canonical_dump` is the byte-comparable serialization the AC is scored
    # on: a normalized, stably-sorted TEXT dump, never the raw `.db` bytes
    # (Notes: "canonical-logical-dump level").
    #
    # Determinism (the whole point of this file): `intents`/`edges`
    # created_at/updated_at are re-stamped from the frontmatter `created:`
    # field AFTER Mirror.cold_rebuild runs, overriding whatever wall-clock
    # `now:` that pass happened to use, so two independent rebuilds of the
    # same fixture store -- even invoked at genuinely different real times --
    # produce an identical dump. `savepoint_events` and the restored
    # queue/batch fields keep the timestamps SavepointEvents.rebuild_from_export
    # already derives from the committed JSONL's own occurred_at values
    # (never Time.now either), so nothing downstream re-introduces wall-clock
    # drift.
    #
    # Composes Mirror + SavepointEvents exactly as built in ACTION_5/ACTION_6;
    # neither is modified here.
    module Rebuild
      module_function

      TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ".freeze

      # Fixed constant for a derived row whose frontmatter carries no
      # `created:` at all (Notes: "and a fixed constant for missing values"),
      # so determinism holds even for that edge case.
      MISSING_CREATED_STAMP = "1970-01-01T00:00:00Z".freeze

      # Full cold rebuild (fail-open: nil conn returns nil, never raises).
      # `now:` only seeds Mirror.cold_rebuild's own bookkeeping stamp
      # (schema_meta.last_full_rebuild_at, legitimately wall-clock: it
      # records WHEN rebuild ran, not intent content) -- every intent/edge
      # row's own created_at/updated_at is overridden right after by
      # `restamp_content_derived_timestamps`, so `now:`'s value never leaks
      # into the comparable dump.
      def rebuild!(conn, store_home:, now: Time.now.utc)
        return nil if conn.nil?

        Plastic::DB.with_write(conn) { |c| c.execute("DELETE FROM savepoint_events") }

        Mirror.cold_rebuild(conn, store_home: store_home, now: now)
        restamp_content_derived_timestamps(conn)
        restore_snapshots(conn, store_home: store_home)

        :rebuilt
      end

      # Canonical, stably-sorted, normalized TEXT dump of every table Rebuild
      # touches (intents, edges, savepoint_events, roadmaps, roadmap_entries).
      # Deliberately excludes: the volatile autoincrement `id` / raw surrogate
      # FK columns (replaced by the human `intent_id`/`slug` they reference)
      # and `schema_meta` (operational bookkeeping about WHEN rebuild ran,
      # not derived intent content -- see the `rebuild!` doc comment above).
      # nil on a nil conn.
      def canonical_dump(conn)
        return nil if conn.nil?

        lines = []
        lines.concat(dump_intents(conn))
        lines.concat(dump_edges(conn))
        lines.concat(dump_savepoint_events(conn))
        lines.concat(dump_roadmaps(conn))
        lines.concat(dump_roadmap_entries(conn))
        lines.join("\n")
      end

      # --- internals: rebuild! steps ------------------------------------------

      # Re-stamp created_at/updated_at on every intents + edges row from
      # content alone: an intent's stamp comes from its own frontmatter
      # `created:`; an edge inherits its SOURCE intent's stamp (an edge has
      # no `created:` of its own). Runs after Mirror.cold_rebuild, which is
      # the one place these columns get an initial (wall-clock-tainted)
      # value; this pass is what makes them deterministic.
      def restamp_content_derived_timestamps(conn)
        Plastic::DB.with_write(conn) do |c|
          c.execute("SELECT id, created FROM intents").each do |id, created|
            stamp = normalize_created(created)
            c.execute("UPDATE intents SET created_at = ?, updated_at = ? WHERE id = ?", [stamp, stamp, id])
          end

          c.execute(
            "SELECT edges.id, intents.created FROM edges JOIN intents ON edges.source_intent_id = intents.id"
          ).each do |edge_id, created|
            stamp = normalize_created(created)
            c.execute("UPDATE edges SET created_at = ?, updated_at = ? WHERE id = ?", [stamp, stamp, edge_id])
          end
        end
      end

      # PURE text transform of the frontmatter `created:` value (a bare date
      # or an ISO8601 timestamp) into the same TEXT ISO8601 shape every other
      # timestamp column uses. No Time.now anywhere in this path.
      def normalize_created(created)
        text = created.to_s.strip
        return MISSING_CREATED_STAMP if text.empty?
        return "#{text}T00:00:00Z" if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        return Time.parse(text).utc.strftime(TIME_FORMAT) if text.match?(/\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/)

        MISSING_CREATED_STAMP
      rescue ArgumentError
        MISSING_CREATED_STAMP
      end

      # One SavepointEvents.rebuild_from_export per intent found on disk,
      # in Mirror's own deterministic (sorted) file order -- reuses
      # Mirror.collect_intent_files rather than re-scanning the store.
      def restore_snapshots(conn, store_home:)
        root = File.join(store_home.to_s, "store")
        Mirror.collect_intent_files(store_home).each do |entry|
          intent_dir = File.join(root, entry[:basename])
          SavepointEvents.rebuild_from_export(conn, intent_id: entry[:intent_id], intent_dir: intent_dir)
        end
      end

      # --- internals: canonical_dump table dumps ------------------------------

      def dump_row(table, values)
        "#{table}|#{values.map { |v| v.nil? ? '' : v.to_s }.join('|')}"
      end
      private_class_method :dump_row

      def dump_intents(conn)
        cols = %w[intent_id title slug tags author created chain sources content_hash status quadrant
                  created_at updated_at]
        conn.execute("SELECT #{cols.join(', ')} FROM intents ORDER BY intent_id")
            .map { |row| dump_row("intents", row) }
      end

      def dump_edges(conn)
        rows = conn.execute(
          "SELECT src.intent_id, edges.kind, edges.position, edges.target_ref, tgt.intent_id, " \
          "edges.created_at, edges.updated_at " \
          "FROM edges JOIN intents src ON edges.source_intent_id = src.id " \
          "LEFT JOIN intents tgt ON edges.target_intent_id = tgt.id " \
          "ORDER BY src.intent_id, edges.kind, edges.position, edges.target_ref"
        )
        rows.map { |row| dump_row("edges", row) }
      end

      def dump_savepoint_events(conn)
        rows = conn.execute(
          "SELECT i.intent_id, se.stage, se.event_type, se.actor_session, se.payload, se.occurred_at " \
          "FROM savepoint_events se JOIN intents i ON se.intent_id = i.id " \
          "ORDER BY i.intent_id, se.occurred_at, se.stage, se.event_type"
        )
        rows.map { |row| dump_row("savepoint_events", row) }
      end

      def dump_roadmaps(conn)
        rows = conn.execute("SELECT slug, title, goal, created_at, updated_at FROM roadmaps ORDER BY slug")
        rows.map { |row| dump_row("roadmaps", row) }
      end

      def dump_roadmap_entries(conn)
        rows = conn.execute(
          "SELECT r.slug, re.intent_id, re.batch_number, re.status, re.position, re.created_at, re.updated_at " \
          "FROM roadmap_entries re JOIN roadmaps r ON re.roadmap_id = r.id " \
          "ORDER BY r.slug, re.intent_id"
        )
        rows.map { |row| dump_row("roadmap_entries", row) }
      end
    end
  end
end
