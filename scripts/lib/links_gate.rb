# encoding: UTF-8
# frozen_string_literal: true

require_relative "intent_validator"
require_relative "links_section"
require_relative "links_projection"
require_relative "store_discovery"
require_relative "graph_rebuild"

# LinksGate, the write-time belt for the PLASTIC.md `## Links` contract
# (intent 192). Pure decision logic plus a small store-scanning glue (mirrors
# the glue ProjectLinks and Doctor each already carry independently for
# themselves; the CALCULATION is shared via LinksSection/LinksProjection so
# gate, projector, and doctor can never disagree by construction, even though
# each IO shell still does its own discovery, exactly as project-links and
# doctor already do today).
#
# #decision is the single entry point the PreToolUse hook
# (scripts/hook-links-gate) calls: given a file path and its BEFORE/AFTER
# content (BEFORE = on-disk, AFTER = the proposed Write/Edit result), it
# returns nil (allow) or a deny message (String). It only ever judges the
# REAL, fence-aware `## Links` section (LinksSection.extract_section); an
# edit that leaves that section untouched is always allowed, cheaply, with no
# store scan at all.
module LinksGate
  module_function

  DENY_MESSAGE =
    "PLASTIC LINKS GATE - a ## Links line must come from the frontmatter " \
    "sources/chain graph, never be hand-typed. This edit changes the ## Links " \
    "section to something other than its frontmatter projection. Add the edge " \
    "to sources or chain in frontmatter instead, then run scripts/project-links " \
    "to regenerate ## Links.".freeze

  # True iff `path` is an intent file inside its own equally-named store
  # directory (store/<id>--<slug>/<id>--<slug>.md). Mirrors the create-gate
  # path matcher (intent 60b) so the two gates agree on what "an intent file" is.
  def intent_file?(path)
    return false if path.to_s.strip.empty?

    abs = File.expand_path(path)
    dir = File.dirname(abs)
    dir.match?(%r{/store/[^/]+--[^/]+\z}) && File.basename(abs) == "#{File.basename(dir)}.md"
  end

  # Decide whether to deny a Write/Edit whose proposed result is
  # `after_content` (the on-disk content before the edit is `before_content`,
  # "" when the file does not yet exist). Returns nil (allow, including every
  # "cannot judge" case) or DENY_MESSAGE.
  def decision(file_path:, before_content:, after_content:, plastic_home:)
    return nil unless intent_file?(file_path)

    before_links = safe_extract(before_content)
    after_links = safe_extract(after_content)
    return nil if before_links.nil? || after_links.nil? # ambiguous ## Links; cannot judge
    return nil if before_links == after_links # this edit does not touch ## Links at all

    fm = IntentValidator.parse_frontmatter_text(after_content.to_s)
    return nil unless fm.is_a?(Hash) # no parseable frontmatter; cannot judge

    referer_store = store_key_for(file_path, plastic_home)
    return nil unless referer_store # not under any discovered store; cannot judge

    ctx = build_context(plastic_home)
    resolve = ->(ref) do
      LinksProjection.resolve_ref_projection(
        ref, referer_store: referer_store, relocation_map: ctx[:relocation_map],
             store_index: ctx[:store_index], node_index: ctx[:node_index]
      )
    end

    expected =
      begin
        LinksProjection.section(sources: Array(fm["sources"]), chain: Array(fm["chain"]),
                                 resolve: resolve)
      rescue LinksProjection::UnresolvedRef
        return nil # a pre-existing dead frontmatter ref is a doctor finding, not this gate's job
      end

    after_links == expected ? nil : DENY_MESSAGE
  end

  # Fence-aware real-section extract, tolerant of an ambiguous file (returns
  # nil rather than raising, so #decision can fail open on it).
  def safe_extract(content)
    LinksSection.extract_section(IntentValidator.body_of(content.to_s))
  rescue LinksSection::AmbiguousLinks
    nil
  end

  # Which discovered store (by store_index/node_index key) `file_path` lives
  # under, or nil when it is not inside any store this plastic_home discovers.
  def store_key_for(file_path, plastic_home)
    abs = File.expand_path(file_path)
    store_dir = File.dirname(File.dirname(abs)) # .../<store>/<id>--<slug>/<file>.md
    StoreDiscovery.discover(plastic_home)[:stores]
      .find { |s| File.expand_path(s[:store]) == store_dir }
      &.fetch(:key)
  end

  # Build the store_index/node_index/relocation_map resolver context spanning
  # every discovered store, the same shape ProjectLinks#run and Doctor each
  # build for themselves. Re-scanned per call (no caching): this only runs on
  # the rare edit that actually changes ## Links, so the cost is paid where it
  # matters, not on every Edit/Write.
  def build_context(plastic_home)
    discovery = StoreDiscovery.discover(plastic_home)
    store_index = {}
    node_index = {}
    index_texts = {}

    discovery[:stores].each do |s|
      nodes = load_nodes(s[:store])
      store_index[s[:key]] = nodes.keys
      node_index[s[:key]] = nodes.transform_values { |v| { basename: v[:basename], label: v[:label] } }
      index_texts[s[:key]] = File.exist?(s[:index]) ? File.read(s[:index]) : ""
    end

    { store_index: store_index, node_index: node_index,
      relocation_map: GraphRebuild.build_relocation_map(index_texts) }
  end

  # { id => { basename:, label: } } for one store directory.
  def load_nodes(store_dir)
    nodes = {}
    Dir.children(store_dir).reject { |e| e.start_with?(".") }.sort.each do |entry|
      dir = File.join(store_dir, entry)
      next unless File.directory?(dir)

      md = File.join(dir, "#{entry}.md")
      next unless File.exist?(md)

      fm = IntentValidator.parse_frontmatter(md)
      next unless fm.is_a?(Hash) && fm["id"]

      nodes[fm["id"].to_s] = { basename: entry, label: fm["intent"].to_s.strip }
    end
    nodes
  end
end
