require "time"
require_relative "../db"

module Plastic
  module DB
    # Roadmaps: the `roadmaps` + `roadmap_entries` tables (D11), authoritative
    # for queue/batch membership (intent 41, ACTION_7). One roadmap (unique
    # `slug`) owns many entries, each pinning one intent to a `batch_number`
    # and an ordering `position` within that roadmap. Fail-open throughout: a
    # nil conn returns nil/[] and never raises, mirroring every other module
    # in this package.
    module Roadmaps
      module_function

      ROADMAP_COLUMNS = %w[id slug title goal created_at updated_at].freeze
      ENTRY_COLUMNS = %w[id roadmap_id intent_id batch_number status position created_at updated_at].freeze

      # Create-or-update a roadmap by its unique slug. Returns the roadmap row
      # Hash, or nil on a nil conn.
      def upsert(conn, slug:, title: nil, goal: nil, now: Time.now)
        return nil if conn.nil?

        stamp = iso(now)
        Plastic::DB.with_write(conn) do |c|
          c.execute(
            "INSERT INTO roadmaps (slug, title, goal, created_at, updated_at) VALUES (?, ?, ?, ?, ?) " \
            "ON CONFLICT(slug) DO UPDATE SET title = excluded.title, goal = excluded.goal, updated_at = excluded.updated_at",
            [slug, title || slug, goal, stamp, stamp]
          )
          find_roadmap(c, slug)
        end
      end

      # Create-or-update one intent's membership in a roadmap. Auto-creates a
      # minimal roadmap row (slug as title) when `roadmap_slug` has no
      # `roadmap_upsert` yet, so this verb never depends on call order.
      # Returns the entry row Hash, or nil on a nil conn.
      def entry_set(conn, roadmap_slug:, intent_id:, batch_number: nil, status: nil, position: nil, now: Time.now)
        return nil if conn.nil?

        stamp = iso(now)
        Plastic::DB.with_write(conn) do |c|
          roadmap = find_roadmap(c, roadmap_slug) || begin
            c.execute(
              "INSERT INTO roadmaps (slug, title, goal, created_at, updated_at) VALUES (?, ?, NULL, ?, ?)",
              [roadmap_slug, roadmap_slug, stamp, stamp]
            )
            find_roadmap(c, roadmap_slug)
          end

          existing_id = c.execute(
            "SELECT id FROM roadmap_entries WHERE roadmap_id = ? AND intent_id = ?",
            [roadmap["id"], intent_id]
          ).dig(0, 0)

          if existing_id
            c.execute(
              "UPDATE roadmap_entries SET batch_number = ?, status = ?, position = ?, updated_at = ? WHERE id = ?",
              [batch_number, status, position, stamp, existing_id]
            )
          else
            c.execute(
              "INSERT INTO roadmap_entries " \
              "(roadmap_id, intent_id, batch_number, status, position, created_at, updated_at) " \
              "VALUES (?, ?, ?, ?, ?, ?, ?)",
              [roadmap["id"], intent_id, batch_number, status, position, stamp, stamp]
            )
          end

          find_entry(c, roadmap["id"], intent_id)
        end
      end

      # Entries for one roadmap (optionally filtered to one batch), ordered by
      # position then intent_id for a deterministic result set. Empty array
      # (never nil) for an unknown slug or a nil conn.
      def entries_for(conn, roadmap_slug, batch: nil)
        return [] if conn.nil?

        roadmap = find_roadmap(conn, roadmap_slug)
        return [] if roadmap.nil?

        sql = "SELECT #{ENTRY_COLUMNS.join(', ')} FROM roadmap_entries WHERE roadmap_id = ?"
        params = [roadmap["id"]]
        if batch
          sql += " AND batch_number = ?"
          params << batch
        end
        sql += " ORDER BY position ASC, intent_id ASC"

        conn.execute(sql, params).map { |row| ENTRY_COLUMNS.zip(row).to_h }
      end

      def find_roadmap(conn, slug)
        row = conn.execute("SELECT #{ROADMAP_COLUMNS.join(', ')} FROM roadmaps WHERE slug = ?", [slug]).first
        row && ROADMAP_COLUMNS.zip(row).to_h
      end

      def find_entry(conn, roadmap_id, intent_id)
        row = conn.execute(
          "SELECT #{ENTRY_COLUMNS.join(', ')} FROM roadmap_entries WHERE roadmap_id = ? AND intent_id = ?",
          [roadmap_id, intent_id]
        ).first
        row && ENTRY_COLUMNS.zip(row).to_h
      end

      def iso(time)
        time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end
    end
  end
end
