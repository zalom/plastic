# encoding: UTF-8
# frozen_string_literal: true

require "digest"
require "time"
require_relative "../intent_validator"

module Plastic
  module DB
    # Mirror — the derived `intents` frontmatter mirror and `edges` graph table
    # (intent 41, ACTION_6). Files win on any conflict; resync is keyed on
    # content_hash of the frontmatter block, NEVER mtime. Authoritative columns
    # (status, quadrant) are never touched by a reconcile pass, only by the
    # record-verb API (ACTION_7). A format_version bump (Schema.rebuild_needed?)
    # forces a full cold_rebuild that ignores content_hash entirely.
    module Mirror
      module_function

      TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

      # Mirrors the bare-id wikilink shape already established by
      # LinkSuggestions#links_refs (scripts/lib/link_suggestions.rb): a target
      # is `[[<id>--<slug>|label]]` or `[[<store>:<id>--<slug>|label]]`.
      WIKILINK_RE = /\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/.freeze

      # PURE. Stable SHA over the frontmatter block TEXT only (mirrors
      # org-roam's SHA-of-content approach). A file touch that leaves the
      # frontmatter byte-identical must never change this.
      def content_hash(frontmatter_text)
        Digest::SHA256.hexdigest(frontmatter_text.to_s)
      end

      # Debounced, content-hash-keyed resync of `intents` + `edges` from every
      # intent file's frontmatter under store_home/store/. A format_version
      # bump bypasses the debounce window entirely and runs a full cold_rebuild.
      # Returns :cold_rebuilt, :debounced, or :reconciled (nil when conn is the
      # fail-open sentinel).
      def reconcile(conn, store_home:, now: Time.now.utc, debounce: 2)
        return nil if conn.nil?
        return cold_rebuild(conn, store_home: store_home, now: now) if Schema.rebuild_needed?(conn)

        last = last_reconcile_time(conn)
        return :debounced if last && (now - last) < debounce

        reconcile_pass(conn, store_home: store_home, now: now)
        :reconciled
      end

      # Full cold pass (AC12): clears `intents` + `edges` and rebuilds every
      # intent from files, ignoring content_hash, so a stale derived row for a
      # file that no longer exists disappears. Resolves edge targets in a
      # second pass, after every intent row exists, so file iteration order
      # never leaves a same-store target unresolved.
      def cold_rebuild(conn, store_home:, now: Time.now.utc)
        return nil if conn.nil?

        Plastic::DB.with_write(conn) do |c|
          c.execute("DELETE FROM edges")
          c.execute("DELETE FROM intents")
        end

        entries = collect_intent_files(store_home)
        entries.each { |e| e[:row_id] = upsert_intent(conn, entry: e, now: now) }
        entries.each { |e| rebuild_edges_for(conn, e[:row_id], entry: e, now: now) }

        stamp_meta(conn, now: now, full_rebuild: true)
        :cold_rebuilt
      end

      # Incremental pass: only intents whose content_hash differs from the
      # stored row are touched; an unchanged file is skipped entirely (no
      # write at all), so unrelated rows are provably untouched (AC11). Two
      # passes over just the changed set (upsert, THEN rebuild edges), same
      # shape as cold_rebuild, so a forward reference between two intents that
      # both changed in the same burst still resolves regardless of file
      # iteration order.
      def reconcile_pass(conn, store_home:, now:)
        return nil if conn.nil?

        changed = collect_intent_files(store_home).reject do |e|
          existing = conn.execute("SELECT content_hash FROM intents WHERE intent_id = ?", [e[:intent_id]]).first
          existing && existing.first == e[:hash]
        end

        changed.each { |e| e[:row_id] = upsert_intent(conn, entry: e, now: now) }
        changed.each { |e| rebuild_edges_for(conn, e[:row_id], entry: e, now: now) }

        stamp_meta(conn, now: now, full_rebuild: false)
      end

      # Upsert the derived columns for one intent (files win). Authoritative
      # columns (status, quadrant) are OMITTED from the UPDATE set, so a
      # reconcile never clobbers them; a brand-new row gets them NULL until the
      # record-verb API sets them.
      # Check-then-insert-or-update runs ENTIRELY inside one with_write (BEGIN
      # IMMEDIATE) transaction, the same discipline Leases.insert_live_row
      # uses: a plain SELECT before the transaction would leave a window
      # where two concurrent reconciles could both see "no existing row" and
      # both attempt an INSERT, tripping the intents.intent_id UNIQUE
      # constraint. Doing the check inside the transaction makes it atomic
      # instead.
      def upsert_intent(conn, entry:, now:)
        fm = entry[:fm]
        stamp = now.strftime(TIME_FORMAT)
        slug = slug_from_basename(entry[:basename], entry[:intent_id])
        created = fm["created"] && fm["created"].to_s
        tags = Array(fm["tags"]).join(",")
        chain = Array(fm["chain"]).join(",")
        sources = Array(fm["sources"]).join(",")

        Plastic::DB.with_write(conn) do |c|
          existing = c.execute("SELECT id FROM intents WHERE intent_id = ?", [entry[:intent_id]]).first

          if existing
            c.execute(
              "UPDATE intents SET title=?, slug=?, tags=?, author=?, created=?, chain=?, sources=?, " \
              "content_hash=?, updated_at=? WHERE id=?",
              [fm["intent"], slug, tags, fm["author"], created, chain, sources, entry[:hash], stamp, existing.first]
            )
          else
            c.execute(
              "INSERT INTO intents (intent_id, title, slug, tags, author, created, chain, sources, " \
              "content_hash, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
              [entry[:intent_id], fm["intent"], slug, tags, fm["author"], created, chain, sources, entry[:hash], stamp, stamp]
            )
          end
        end

        conn.execute("SELECT id FROM intents WHERE intent_id = ?", [entry[:intent_id]]).first.first
      end

      # Delete + reinsert one intent's edges: chain -> kind "chain", sources ->
      # kind "sources", prose `[[..]]` links anywhere in the body -> kind
      # "link". target_intent_id resolves to the local `intents.id` when that
      # ref exists in THIS store; a cross-store ref (or a same-store dangler)
      # leaves target_intent_id NULL without error.
      def rebuild_edges_for(conn, source_row_id, entry:, now:)
        stamp = now.strftime(TIME_FORMAT)
        fm = entry[:fm]
        Plastic::DB.with_write(conn) do |c|
          c.execute("DELETE FROM edges WHERE source_intent_id = ?", [source_row_id])
          insert_edge_kind(c, source_row_id, Array(fm["sources"]), "sources", stamp)
          insert_edge_kind(c, source_row_id, Array(fm["chain"]), "chain", stamp)
          insert_edge_kind(c, source_row_id, wikilink_targets(entry[:body]), "link", stamp)
        end
      end

      def insert_edge_kind(conn, source_row_id, refs, kind, stamp)
        Array(refs).each_with_index do |ref, position|
          ref = ref.to_s
          conn.execute(
            "INSERT INTO edges (source_intent_id, target_ref, target_intent_id, kind, position, " \
            "created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
            [source_row_id, ref, resolve_local_id(conn, ref), kind, position, stamp, stamp]
          )
        end
      end

      # NULL (soft ref, no FK violation) for a cross-store ref or a same-store
      # id with no local row; the local intents.id otherwise.
      def resolve_local_id(conn, ref)
        return nil if ref.include?(":")

        row = conn.execute("SELECT id FROM intents WHERE intent_id = ?", [ref]).first
        row && row.first
      end

      # Scan every `<store_home>/store/<id>--<slug>/<id>--<slug>.md` file,
      # sorted by directory name for deterministic rebuild order (AC3). Skips
      # anything unparsable rather than raising, so one malformed intent file
      # never blocks the whole store's reconcile.
      def collect_intent_files(store_home)
        root = File.join(store_home.to_s, "store")
        return [] unless Dir.exist?(root)

        Dir.children(root).sort.filter_map do |name|
          dir = File.join(root, name)
          next nil unless File.directory?(dir)

          md_path = File.join(dir, "#{name}.md")
          next nil unless File.exist?(md_path)

          content = File.read(md_path)
          fm = IntentValidator.parse_frontmatter_text(content)
          next nil unless fm.is_a?(Hash) && fm["id"]

          {
            basename: name,
            intent_id: fm["id"].to_s,
            fm: fm,
            body: IntentValidator.body_of(content),
            hash: content_hash(frontmatter_text_of(content)),
          }
        end
      end

      # The raw frontmatter block TEXT (the same split IntentValidator uses
      # internally to parse it), so content_hash is computed over exactly what
      # a frontmatter-only edit changes, never the body, never mtime.
      def frontmatter_text_of(content)
        return "" unless content.to_s.start_with?("---")

        parts = content.split("---", 3)
        parts.length < 3 ? "" : parts[1]
      end

      # The slug half of an `<id>--<slug>` directory basename.
      def slug_from_basename(basename, intent_id)
        prefix = "#{intent_id}--"
        basename.start_with?(prefix) ? basename[prefix.length..] : basename
      end

      # PURE. Bare-id (or `store:id`) targets of every `[[..]]` wikilink in the
      # body, fence-skipped so an example wikilink inside a code block is never
      # picked up. A wikilink target carries the `<id>--<slug>` basename (or
      # `<store>:<id>--<slug>` cross-store form); only the id half is kept.
      def wikilink_targets(body)
        strip_fences(body).scan(WIKILINK_RE).filter_map { |match| normalize_wikilink_ref(match.first.strip) }.uniq
      end

      def strip_fences(body)
        out = []
        in_fence = false
        body.to_s.each_line do |line|
          stripped = line.strip
          if stripped.start_with?("```")
            in_fence = !in_fence
            next
          end
          out << line unless in_fence
        end
        out.join
      end

      def normalize_wikilink_ref(ref)
        return nil if ref.nil? || ref.empty?

        if ref.include?(":")
          store, rest = ref.split(":", 2)
          id = rest.to_s.split("--", 2).first
          id.nil? || id.empty? ? nil : "#{store}:#{id}"
        else
          id = ref.split("--", 2).first
          id.nil? || id.empty? ? nil : id
        end
      end

      def last_reconcile_time(conn)
        row = conn.execute("SELECT last_reconcile_at FROM schema_meta WHERE id = 1").first
        value = row && row.first
        return nil if value.nil? || value.to_s.empty?

        Time.parse(value.to_s)
      end

      def stamp_meta(conn, now:, full_rebuild:)
        stamp = now.strftime(TIME_FORMAT)
        Plastic::DB.with_write(conn) do |c|
          if full_rebuild
            c.execute(
              "UPDATE schema_meta SET format_version=?, last_full_rebuild_at=?, last_reconcile_at=?, updated_at=? WHERE id=1",
              [Schema::FORMAT_VERSION, stamp, stamp, stamp]
            )
          else
            c.execute("UPDATE schema_meta SET last_reconcile_at=?, updated_at=? WHERE id=1", [stamp, stamp])
          end
        end
      end
    end
  end
end
