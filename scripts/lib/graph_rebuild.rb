# encoding: UTF-8
# frozen_string_literal: true

# GraphRebuild — pure logic for repairing the store-wide sources/chain graph
# (intent 49). Mirrors the pure-module style of IntentValidator: module-function
# helpers with no file IO. The IO shell (scripts/rebuild-graph) and doctor build
# the in-memory maps and feed them here.
#
# Two concerns live here:
#   1. Cross-store relocation. Each store's INDEX.md `## Relocated` log records
#      moves like `global:24 → project:22c` (or backtick bare-id form `1b1a1 → 41`).
#      build_relocation_map parses every log into a multi-hop-collapsed map; the
#      resolver consults it BEFORE direct id resolution so a relocation always wins
#      over a coincidentally-reused id (the `global:24` impostor hazard).
#   2. The per-intent rebuild transform (intent 68 I-invariants, one-directional):
#      dedupe -> I3 (formative edge wins) -> cross-store resolve -> I1 backlinks ->
#      I2 preserved (relational chains survive).
module GraphRebuild
  module_function

  RELOCATION_ARROW = "→" # the unicode → used in every Relocated log

  # PURE. Parse every store's INDEX.md `## Relocated` block into a multi-hop
  # relocation map.
  #
  # `index_texts` is { store_key => index_md_string } where store_key is "global"
  # or "project:<slug>". Returns { [from_store, from_id] => [to_store, to_id] }
  # with chains transitively collapsed to their final hop. The `to_store` token is
  # NORMALIZED: the generic `project:` token in the global log is left as the
  # literal it appears with; resolve_ref maps a same-family target to a bare id.
  #
  # Two real arrow forms are handled:
  #   - `global:24 → project:22c`   (store-prefixed, global log)
  #   - `1b1a1 → 41` inside backticks (bare ids, plastic log) — these are
  #     same-store moves; from/to store both default to the store the log lives in.
  def build_relocation_map(index_texts)
    raw = {}
    (index_texts || {}).each do |store_key, text|
      next unless text.is_a?(String)

      relocated_block(text).each_line do |line|
        parse_relocation_line(line, store_key).each do |(from, to)|
          raw[from] = to
        end
      end
    end
    collapse_multi_hop(raw)
  end

  # Extract the text of the `## Relocated` section (everything from the heading to
  # the next top-level `## ` heading or EOF). Returns "" when absent.
  def relocated_block(text)
    lines = text.lines
    start = lines.index { |l| l.strip == "## Relocated" }
    return "" if start.nil?

    rest = lines[(start + 1)..] || []
    stop = rest.index { |l| l.start_with?("## ") }
    (stop ? rest[0...stop] : rest).join
  end

  # Parse one log line into an array of [[from_store, from_id], [to_store, to_id]]
  # pairs. A line may pack several comma-separated pairs and carry trailing prose
  # in parens. Lines without an arrow yield []. `home_store` is the store whose
  # log this line came from (used as the default store for bare ids).
  def parse_relocation_line(line, home_store)
    body = line.sub(/\A\s*-\s*/, "") # drop list bullet
    return [] unless body.include?(RELOCATION_ARROW)

    body.split(",").filter_map do |segment|
      seg = segment.strip
      next nil unless seg.include?(RELOCATION_ARROW)

      left, right = seg.split(RELOCATION_ARROW, 2)
      from = parse_token(left, home_store)
      to = parse_token(right, home_store)
      next nil if from.nil? || to.nil?

      [from, to]
    end
  end

  # Parse a single `store:id` / bare-id token (possibly wrapped in backticks or
  # trailed by parenthetical prose) into [store_key, bare_id], or nil. A bare id
  # defaults to `home_store`. The generic `project:` prefix is resolved later by
  # resolve_ref against the referer's store family; here it is recorded literally.
  def parse_token(token, home_store)
    cleaned = token.to_s.tr("`", " ").strip
    cleaned = cleaned.sub(/\s*\(.*\z/, "").strip # drop trailing "(prose"
    cleaned = cleaned.split(/\s/).first.to_s     # first whitespace-delimited atom
    return nil if cleaned.empty?

    if cleaned.include?(":")
      store_tok, id = cleaned.split(":", 2)
      return nil if id.to_s.empty?

      [normalize_store_token(store_tok), id]
    else
      [home_store, cleaned]
    end
  end

  # Normalize a store token from a log to a store_key. "global" stays "global".
  # The generic "project" token (used in the global log) is kept as the sentinel
  # "project" — resolve_ref binds it to the referer's project family.
  def normalize_store_token(tok)
    t = tok.to_s.strip
    t == "global" ? "global" : t
  end

  # Transitively collapse a → b → c chains so every key maps to its FINAL hop.
  # Cycle-guarded. Keys/values are [store_key, id] pairs.
  def collapse_multi_hop(raw)
    raw.each_with_object({}) do |(from, _to), acc|
      seen = [from]
      cur = raw[from]
      while cur && raw.key?(cur) && !seen.include?(cur)
        seen << cur
        cur = raw[cur]
      end
      acc[from] = cur
    end
  end

  # PURE. Resolve a single ref (a `store:id` cross-store ref, or a bare same-store
  # id) to a final location and classification. ORDER IS LOAD-BEARING: the
  # relocation map is consulted FIRST, so a relocation wins over a coincidentally
  # reused id.
  #
  #   ref             — "global:24" or "22c"
  #   referer_store   — store_key of the intent carrying the ref ("global"/"project:plastic")
  #   relocation_map  — from build_relocation_map
  #   store_index     — { store_key => Array/Set of bare ids present in that store }
  #
  # Returns a Hash:
  #   { status: :same_store, id: "<bare id>" }              -> collapse to bare id
  #   { status: :cross_store, ref: "<store>:<id>" }         -> keep/repoint store:id
  #   { status: :dead, ref: <original> }                    -> drop (resolves nowhere)
  def resolve_ref(ref, referer_store:, relocation_map:, store_index:)
    store_tok, bare = split_ref(ref, referer_store)

    # 1) Relocation FIRST. Look up [store, id]; the generic "project" target token
    #    is bound to the referer's family when emitting the location.
    reloc_key = [store_tok, bare]
    if (relocation_map || {}).key?(reloc_key)
      to_store, to_id = relocation_map[reloc_key]
      to_store = bind_project_token(to_store, referer_store, store_index, to_id)
      return classify(to_store, to_id, referer_store, store_index, ref)
    end

    # 2) Direct resolution against the live store index.
    classify(store_tok, bare, referer_store, store_index, ref)
  end

  # Split a ref into [store_key, bare_id]; bare refs take the referer's store.
  def split_ref(ref, referer_store)
    s = ref.to_s
    if s.include?(":")
      store_tok, id = s.split(":", 2)
      [normalize_store_token(store_tok), id]
    else
      [referer_store, s]
    end
  end

  # The global log writes relocation targets as the generic `project:` token. Bind
  # it to the concrete store family that actually owns the bare id. Prefer the
  # referer's store when it holds the id; otherwise pick any store that has it.
  def bind_project_token(to_store, referer_store, store_index, to_id)
    return to_store unless to_store == "project"

    return referer_store if ids_in(store_index, referer_store).include?(to_id)

    owner = (store_index || {}).keys.find { |k| ids_in(store_index, k).include?(to_id) }
    owner || referer_store
  end

  # Map a ref store token to the canonical store_index key. Refs in frontmatter
  # use the slug form (`global`, `knowdb`, `plastic`); store_index keys use
  # `global` and `project:<slug>`. "global" is canonical; anything else maps to
  # `project:<token>` when that key exists, else the token itself (it may already
  # be a `project:<slug>` key, e.g. a relocation target).
  def canonical_store_key(store_tok, store_index)
    return store_tok if store_tok == "global"
    return store_tok if (store_index || {}).key?(store_tok)

    projected = "project:#{store_tok}"
    (store_index || {}).key?(projected) ? projected : store_tok
  end

  # The slug form of a canonical store key, for emitting a cross-store `slug:id`
  # ref (the form used in frontmatter). "global" stays "global"; "project:<slug>"
  # becomes "<slug>".
  def slug_of(canonical_key)
    canonical_key.to_s.sub(/\Aproject:/, "")
  end

  # Classify a resolved (store, id) relative to the referer, using the live store
  # index to detect dead targets:
  #   - the store token resolves to no known store          -> :unknown_store (NEVER
  #     dropped; this is what makes a future discovery miss non-destructive, intent 189 D2)
  #   - target id present in the referer's OWN known store   -> :same_store (collapse)
  #   - target id present in a DIFFERENT known store          -> :cross_store (keep slug:id)
  #   - target id present NOWHERE in a known store            -> :dead (drop)
  def classify(store_tok, bare, referer_store, store_index, original_ref)
    canonical = canonical_store_key(store_tok, store_index)
    unless known_store?(canonical, store_index)
      return { status: :unknown_store, ref: original_ref.to_s, store: store_tok }
    end

    if ids_in(store_index, canonical).include?(bare)
      if canonical == referer_store
        { status: :same_store, id: bare }
      else
        { status: :cross_store, ref: "#{slug_of(canonical)}:#{bare}" }
      end
    else
      { status: :dead, ref: original_ref.to_s }
    end
  end

  # True iff `canonical` names a store this run actually knows about (it is "global", or a
  # literal key in `store_index`). A ref whose store token canonicalizes to anything else
  # has never been discovered by this run, and must be classified :unknown_store, never
  # :dead: those are different facts (store unknown vs. id absent from a known store) and
  # only the second one means the ref is genuinely gone.
  def known_store?(canonical, store_index)
    canonical == "global" || (store_index || {}).key?(canonical)
  end

  def ids_in(store_index, store_key)
    Array((store_index || {})[store_key])
  end

  # PURE. Per-store rebuild transform (intent 68 I-invariants, one-directional).
  # Deterministic and idempotent: a second call over the result yields zero changes.
  #
  #   nodes          — ONE store's { id => { sources: [...], chain: [...] } } map
  #   referer_store  — that store's key ("global" / "project:<slug>")
  #   relocation_map — from build_relocation_map (spans all stores)
  #   store_index    — { store_key => bare ids present } (spans all stores)
  #
  # Returns { nodes: <new map>, changes: [ {intent:, kind:, before:, after:} ],
  #           preserved: [ {intent:, field:, ref:, store:} ] }.
  # kinds (changes, real mutations only): :dedupe, :i3, :repoint, :collapse, :drop,
  # :i1_backlink. `preserved` is DIFFERENT: an unknown-store ref left byte-for-byte
  # unchanged, reported for visibility, never counted as a "change" (nothing mutated).
  #
  # Order is load-bearing (spec Phase 2):
  #   1. dedupe each array order-preserving
  #   2. I3: an id in BOTH sources and chain is kept in sources, dropped from chain
  #   3. cross-store resolve each ref (relocation FIRST): repoint, collapse to bare
  #      same-store, or drop dead
  #   4. I1: for every in-store source s, ensure s.chain backlinks this intent
  #   5. I2 preserved: never synthesize a reciprocal source, never strip a
  #      relational chain entry
  def rebuild_store(nodes, referer_store:, relocation_map:, store_index:)
    out = {}
    (nodes || {}).each do |id, edges|
      edges = {} unless edges.is_a?(Hash)
      out[id.to_s] = {
        sources: Array(edges[:sources] || edges["sources"]).map(&:to_s),
        chain: Array(edges[:chain] || edges["chain"]).map(&:to_s),
      }
    end

    changes = []
    preserved = []

    out.each do |id, edges|
      # 1. dedupe order-preserving
      deduped_sources = edges[:sources].uniq
      deduped_chain = edges[:chain].uniq
      if deduped_sources != edges[:sources] || deduped_chain != edges[:chain]
        changes << { intent: id, kind: :dedupe,
                     before: { sources: edges[:sources].dup, chain: edges[:chain].dup },
                     after: { sources: deduped_sources, chain: deduped_chain } }
      end
      edges[:sources] = deduped_sources
      edges[:chain] = deduped_chain

      # 2. I3: overlap kept in sources, dropped from chain
      overlap = edges[:sources] & edges[:chain]
      overlap.each do |o|
        changes << { intent: id, kind: :i3, before: o, after: nil }
      end
      edges[:chain] -= overlap unless overlap.empty?

      # 3. cross-store resolve sources and chain
      %i[sources chain].each do |field|
        rebuilt = []
        edges[field].each do |ref|
          unless ref.include?(":")
            rebuilt << ref # bare same-store id, left as-is here (I4 is doctor's job)
            next
          end

          res = resolve_ref(ref, referer_store: referer_store,
                                 relocation_map: relocation_map, store_index: store_index)
          case res[:status]
          when :same_store
            if res[:id] != ref
              changes << { intent: id, kind: :collapse, field: field, before: ref, after: res[:id] }
            end
            rebuilt << res[:id]
          when :cross_store
            if res[:ref] != ref
              changes << { intent: id, kind: :repoint, field: field, before: ref, after: res[:ref] }
            end
            rebuilt << res[:ref]
          when :unknown_store
            # NEVER drop: the store is unrecognized, not the id absent from a known store.
            # Preserve byte-for-byte and report separately from `changes` (nothing mutated).
            preserved << { intent: id, field: field, ref: ref, store: res[:store] }
            rebuilt << ref
          when :dead
            changes << { intent: id, kind: :drop, field: field, before: ref, after: nil }
            # dropped: not appended
          end
        end
        # de-dupe again after collapse/repoint may have created duplicates
        edges[field] = rebuilt.uniq
      end

      # 3b. Re-apply I3 AFTER resolution: a cross-store ref that collapses to a
      #     bare same-store id can newly overlap an existing chain entry (e.g.
      #     sources:[global:14a]→[19a] meeting chain:[19a]). Formative edge wins.
      post_overlap = edges[:sources] & edges[:chain]
      post_overlap.each do |o|
        changes << { intent: id, kind: :i3, before: o, after: nil }
      end
      edges[:chain] -= post_overlap unless post_overlap.empty?
    end

    # 4. I1: in-store source backlinks (mutates OTHER nodes). Runs after resolution
    #    so collapsed bare ids participate. Order-preserving append.
    out.each do |id, edges|
      edges[:sources].each do |s|
        next if s.include?(":")        # cross-store: backlink lives in another store
        next unless out.key?(s)        # unresolved bare id is an I4 dangler, not I1
        next if out[s][:chain].include?(id)

        before_chain = out[s][:chain].dup
        out[s][:chain] = out[s][:chain] + [id]
        changes << { intent: s, kind: :i1_backlink, field: :chain,
                     before: before_chain, after: out[s][:chain].dup, backlink: id }
      end
    end

    { nodes: out, changes: changes, preserved: preserved }
  end
end
