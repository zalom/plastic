# encoding: UTF-8
# frozen_string_literal: true

# LinksProjection — pure logic that projects one intent's sources/chain graph into
# the canonical I5 `## Links` section text (intent 72). Mirrors the pure-module
# style of GraphRebuild: module-function helpers, no file IO, no eval, no
# ENV/global state. The IO shell (scripts/project-links) and doctor build the
# cross-store resolver and feed it here.
#
# Pinned canonical projection (the human's format call):
#   1. ORDERING (load-bearing): ALL sources first, in frontmatter order, THEN all
#      chain, in frontmatter order. Sources can NEVER appear at the end. No group
#      headings, no per-entry source/chain tags: the ordering carries the meaning.
#   2. ENTRY SHAPE: one list item `- [[<id>--<slug>|<target's full intent: text>]]`,
#      where the wikilink TARGET is the target intent's resolvable `id--slug` file
#      basename (so it clicks through in Obsidian) and the LABEL is the target's
#      full `intent:` frontmatter text, whitespace-trimmed.
#   3. CROSS-STORE: a cross-store target renders
#      `- [[<store>:<id>--<slug>|<target's full intent: text>]]`.
#   4. RESOLVER MISS: a ref that resolves to no intent raises UnresolvedRef. No
#      bare-id, slug-less, or guessed link is ever emitted.
#   5. EMPTY-STATE: empty sources AND chain yields the heading plus a single
#      explanatory comment.
module LinksProjection
  module_function

  HEADING = "## Links"
  EMPTY_COMMENT = "<!-- No sources or chain; this intent has no graph edges to project. -->"

  # Raised when a sources/chain ref resolves to no intent. Carries the offending
  # ref so the IO shell can report it per-intent and skip the write.
  class UnresolvedRef < StandardError
    attr_reader :ref

    def initialize(ref)
      @ref = ref
      super("unresolved sources/chain ref: #{ref.inspect}")
    end
  end

  # PURE. Build the canonical `## Links` section text for one intent.
  #
  #   sources — array of id / `store:id` ref strings, in frontmatter order
  #   chain   — array of id / `store:id` ref strings, in frontmatter order
  #   resolve — a callable (`->(ref) { ... }`) mapping ONE ref to a Hash like
  #             { target: "<id>--<slug>",            label: "<full intent: text>" } or
  #             { target: "<store>:<id>--<slug>",    label: "<full intent: text>" }.
  #             Returning nil (or a Hash lacking :target) signals no target and
  #             raises UnresolvedRef. Keeping resolution injected keeps this module
  #             pure and hermetically testable with in-memory maps.
  #
  # Returns the full section text: the `## Links` heading line, one entry line per
  # ref (sources first, then chain), and a single trailing newline. The empty case
  # returns the heading + the empty-state comment + a single trailing newline.
  def section(sources:, chain:, resolve:)
    src = Array(sources).map(&:to_s)
    chn = Array(chain).map(&:to_s)

    # Resolve EVERY ref to its { target:, label: } first, then dedup by the RESOLVED
    # target (not the raw ref string). This is load-bearing: the same intent may be
    # referenced as a bare id in one group and as `store:id` in another (or via a
    # relocation), which dedups identically only AFTER resolution. Sources win
    # (formative edge), and frontmatter order is preserved within each group.
    seen = {}
    rendered = []
    src.each { |ref| add_entry(ref, resolve, seen, rendered) }
    chn.each { |ref| add_entry(ref, resolve, seen, rendered) }

    return empty_section if rendered.empty?

    (["#{HEADING}\n"] + rendered.map { |line| "#{line}\n" }).join
  end

  # PURE. The canonical empty-state section: heading + the single comment line.
  def empty_section
    "#{HEADING}\n#{EMPTY_COMMENT}\n"
  end

  # Resolve `ref`, render its entry, and append it to `rendered` UNLESS its resolved
  # target was already emitted (dedup by resolved target, first-seen wins so sources
  # precede chain). Mutates `seen` and `rendered`. Raises UnresolvedRef on a miss.
  def add_entry(ref, resolve, seen, rendered)
    target, label = resolve_entry(ref, resolve)
    return if seen.key?(target)

    seen[target] = true
    rendered << "- [[#{target}|#{label}]]"
  end

  # PURE. Resolve one ref to [target, label]. Raises UnresolvedRef when the
  # resolver returns nothing usable.
  def resolve_entry(ref, resolve)
    resolved = resolve.call(ref)
    target = resolved.is_a?(Hash) ? resolved[:target] || resolved["target"] : nil
    raise UnresolvedRef, ref if target.nil? || target.to_s.strip.empty?

    label = (resolved[:label] || resolved["label"]).to_s.strip
    [target.to_s, label]
  end

  # PURE. Render one entry line `- [[<target>|<label>]]` from a single ref. Kept for
  # callers/tests that render one entry; #section uses add_entry for dedup.
  def entry(ref, resolve)
    target, label = resolve_entry(ref, resolve)
    "- [[#{target}|#{label}]]"
  end

  # PURE. Resolve ONE sources/chain ref to its `{ target:, label: }` projection,
  # given the in-memory cross-store maps. This is the single resolver definition
  # shared by the IO shell (scripts/project-links) and the doctor check, so the two
  # can never diverge.
  #
  #   ref            — "40" (same-store bare id) or "knowdb:1" (cross-store)
  #   referer_store  — store_key of the intent carrying the ref ("global" / "project:<slug>")
  #   relocation_map — from GraphRebuild.build_relocation_map (spans all stores)
  #   store_index    — { store_key => [bare ids present] } (spans all stores)
  #   node_index     — { store_key => { id => { basename:, label: } } } (spans all stores)
  #
  # Returns { target:, label: } (target is `<id>--<slug>` for a same-store id, or
  # `<slug>:<id>--<slug>` for a cross-store one), or nil when the ref resolves to no
  # live intent (which makes #section / #entry raise UnresolvedRef).
  #
  # Uses GraphRebuild.resolve_ref so a relocation always wins over a coincidentally
  # reused id (the `global:24` impostor hazard), exactly as the frontmatter rebuild
  # and the cross-store doctor check do.
  def resolve_ref_projection(ref, referer_store:, relocation_map:, store_index:, node_index:)
    require_relative "graph_rebuild"

    res = GraphRebuild.resolve_ref(ref, referer_store: referer_store,
                                        relocation_map: relocation_map,
                                        store_index: store_index)
    case res[:status]
    when :same_store
      node = (node_index[referer_store] || {})[res[:id]]
      return nil if node.nil?

      { target: node[:basename], label: node[:label] }
    when :cross_store
      slug, bare = res[:ref].split(":", 2)
      target_key = canonical_store_key(slug, store_index)
      node = (node_index[target_key] || {})[bare]
      return nil if node.nil?

      { target: "#{slug}:#{node[:basename]}", label: node[:label] }
    else # :dead
      nil
    end
  end

  # Map a ref store slug ("global", "knowdb", "plastic") to a node_index/store_index
  # key ("global", "project:knowdb", "project:plastic"). Mirrors
  # GraphRebuild.canonical_store_key's intent for the node_index keyspace.
  def canonical_store_key(slug, store_index)
    return "global" if slug == "global"
    return slug if (store_index || {}).key?(slug)

    projected = "project:#{slug}"
    (store_index || {}).key?(projected) ? projected : slug
  end
end
