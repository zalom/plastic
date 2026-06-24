# encoding: UTF-8
# frozen_string_literal: true

# LinkSuggestions - support links decided by CONTEXT INFLUENCE (intent 91, D7), not
# by shared files, shared symbols, or a topic-similarity score. A script cannot judge
# whether one intent's context influenced another (that is reasoning over meaning), so
# this helper does NOT grade. It only:
#
#   - gather:      DISCOVERY. Find candidate intents (via an injected candidate-finder)
#                  and surface each candidate's `## Intent` + `## Context` as the
#                  EVIDENCE an agent reads to judge influence.
#   - record_edge: record a CONFIRMED `sources`/`chain` frontmatter edge AND append a
#                  line to `link-decisions.md` (utc, target, edge, rating, reason).
#                  Append-only, frontmatter block only, never a `## Links` line,
#                  never a delete. A no-op without confirm: true.
#   - drift:       flag any `## Links` wikilink with no matching frontmatter edge.
#
# Two systems frame this:
#   - System for Brain: links are tiered by context influence (sources = foundational
#     context that shaped creation; chain = the genuinely delivery-moving context, a
#     HIGH bar; tags = loose theme grouping, not a link). The influence judgement is
#     made by an agent, not here.
#   - System for Work (Convention over Configuration): `## Links` is a derived view of
#     `sources`/`chain`. This helper never authors a `## Links` line and never deletes.
#
# Design rules: all collaborators are injected via the constructor (the store dir, a
# filesystem reader, AND a candidate-finder). No eval, no ENV / global config seam.
# Reuses IntentValidator.parse_frontmatter; does NOT touch LinksProjection /
# LinksSection / project-links / doctor.

require "time"
require_relative "intent_validator"

class LinkSuggestions
  # One discovery candidate plus the evidence an agent reads to judge influence.
  Candidate = Struct.new(:id, :basename, :label, :intent, :context, keyword_init: true)

  # A drift finding: a `## Links` ref with no matching `sources`/`chain` edge.
  Drift = Struct.new(:ref, :detail, keyword_init: true)

  RATINGS = %w[high medium low].freeze

  # A minimal default filesystem reader. Injected so tests can substitute an
  # in-memory map; the production path reads real files. No global state.
  class DiskReader
    def directory?(path)
      File.directory?(path)
    end

    def children(path)
      Dir.children(path)
    end

    def exist?(path)
      File.exist?(path)
    end

    def read(path)
      File.read(path)
    end

    def write(path, content)
      File.write(path, content)
    end
  end

  # Default candidate-finder: a cheap discovery net (NOT a grade) over the loaded
  # nodes - candidates that share a non-project tag, share a `sources` parent/family,
  # or sit at an adjacent id. The CLI may inject a QMD-backed finder instead. Either
  # way this is DISCOVERY ONLY; influence is judged later by an agent.
  class FamilyTagFinder
    def call(subject_id, nodes)
      subject = nodes[subject_id]
      return [] unless subject

      nodes.keys.select do |other_id|
        next false if other_id == subject_id

        other = nodes[other_id]
        shares_tag?(subject, other) || shares_family?(subject, other) ||
          adjacent_id?(subject_id, other_id)
      end
    end

    private

    def shares_tag?(subject, other)
      !(link_tags(subject) & link_tags(other)).empty?
    end

    def link_tags(node)
      node[:tags].reject { |t| t.start_with?("project-") }
    end

    def shares_family?(subject, other)
      return true unless (subject[:sources] & other[:sources]).empty?

      subject[:sources].include?(other[:id]) || other[:sources].include?(subject[:id])
    end

    # Adjacent ids (discovery hint only): equal non-numeric prefix with integers
    # differing by 1 (9<->10, 99<->100, 90<->91), or a letter successor at the same
    # depth (66a<->66b). This is NOT a grade; it only widens the candidate net.
    def adjacent_id?(a, b)
      return false if a == b || a.empty? || b.empty?

      ma = a.match(/\A(.*?)(\d+)\z/)
      mb = b.match(/\A(.*?)(\d+)\z/)
      return (ma[2].to_i - mb[2].to_i).abs == 1 if ma && mb && ma[1] == mb[1]

      return false unless a.length == b.length

      a[0..-2] == b[0..-2] && a[-1].match?(/[a-z]/) && b[-1].match?(/[a-z]/) &&
        (a[-1].succ == b[-1] || b[-1].succ == a[-1])
    end
  end

  # store_dir - the directory holding `id--slug/` intent folders for ONE store.
  # reader    - injected filesystem collaborator (DiskReader by default).
  # finder    - injected candidate-finder responding to #call(subject_id, nodes).
  def initialize(store_dir:, reader: DiskReader.new, finder: FamilyTagFinder.new)
    @store_dir = store_dir
    @reader = reader
    @finder = finder
  end

  attr_reader :store_dir, :reader, :finder

  # Load every intent in the store as a node Hash keyed by id:
  #   { id => { id:, basename:, label:, path:, dir:, sources:[], chain:[], tags:[],
  #             links_refs:[], intent:, context: } }
  def load_nodes
    nodes = {}
    return nodes unless reader.directory?(store_dir)

    reader.children(store_dir).reject { |e| e.start_with?(".") }.sort.each do |entry|
      dir = File.join(store_dir, entry)
      next unless reader.directory?(dir)

      md = File.join(dir, "#{entry}.md")
      next unless reader.exist?(md)

      content = reader.read(md)
      fm = IntentValidator.parse_frontmatter_text(content)
      next unless fm.is_a?(Hash) && fm["id"]

      id = fm["id"].to_s
      body = IntentValidator.body_of(content)
      nodes[id] = {
        id: id,
        basename: entry,
        label: fm["intent"].to_s.strip,
        path: md,
        dir: dir,
        sources: Array(fm["sources"]).map(&:to_s),
        chain: Array(fm["chain"]).map(&:to_s),
        tags: Array(fm["tags"]).map(&:to_s),
        links_refs: links_refs(body),
        intent: section_text(body, "Intent"),
        context: section_text(body, "Context"),
      }
    end
    nodes
  end

  # DISCOVERY. The candidate intents for `subject_id`, each carrying its Intent +
  # Context as the evidence an agent reads to judge influence. No grading. Sorted by
  # natural id order for stable output.
  def gather(subject_id, nodes: load_nodes)
    return [] unless nodes.key?(subject_id)

    ids = finder.call(subject_id, nodes)
    ids.uniq.sort_by { |id| natural_key(id) }.filter_map do |id|
      node = nodes[id]
      next unless node

      Candidate.new(id: id, basename: node[:basename], label: node[:label],
                    intent: node[:intent], context: node[:context])
    end
  end

  # Record a single CONFIRMED edge from `subject_id` to `target_id`:
  #   1. append `target_id` to the subject's frontmatter `sources` or `chain`;
  #   2. append a line to `link-decisions.md` in the subject dir capturing
  #      {utc, target, edge, rating, reason}.
  # Append-only, frontmatter block only. NEVER writes a `## Links` line, NEVER
  # deletes. A no-op (returns false) without confirm: true, so a default run mutates
  # nothing. Returns true when it wrote, false when it declined or the edge existed.
  def record_edge(subject_id, target_id, edge:, rating: nil, reason: nil,
                  confirm: false, now: Time.now, nodes: load_nodes)
    return false unless confirm
    return false unless %i[sources chain].include?(edge)

    subject = nodes[subject_id]
    return false unless subject
    return false if subject[edge].include?(target_id)

    content = reader.read(subject[:path])
    updated = add_frontmatter_ref(content, edge.to_s, target_id)
    return false if updated == content

    reader.write(subject[:path], updated)
    append_decision(subject, target_id, edge, rating, reason, now)
    true
  end

  # DRIFT. The `## Links` refs on `subject_id` with no matching `sources`/`chain`
  # frontmatter edge behind them. Fence-skipping is honored so a `[[id]]` inside an
  # example code block is not flagged.
  def drift(subject_id, nodes: load_nodes)
    subject = nodes[subject_id]
    return [] unless subject

    edges = (subject[:sources] + subject[:chain]).map { |r| bare_ref(r) }
    subject[:links_refs].reject { |r| edges.include?(bare_ref(r)) }.map do |ref|
      Drift.new(ref: ref,
                detail: "`## Links` references #{ref} with no sources/chain edge behind it")
    end
  end

  private

  # Append one decision line to `link-decisions.md` in the subject's dir, creating the
  # ledger with a header when absent. Append-only; never rewrites prior lines.
  def append_decision(subject, target_id, edge, rating, reason, now)
    ledger = File.join(subject[:dir], "link-decisions.md")
    stamp = now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    line = "#{stamp} | #{target_id} | #{edge} | #{rating || "-"} | #{reason || "-"}"

    if reader.exist?(ledger)
      existing = reader.read(ledger)
      reader.write(ledger, existing.rstrip + "\n" + line + "\n")
    else
      header = "# Link decisions (intent 91 D6): utc | target | edge | rating | reason\n\n"
      reader.write(ledger, header + line + "\n")
    end
  end

  # Natural sort key for ids so 2 sorts before 10 and 14a groups with 14.
  def natural_key(id)
    id.scan(/\d+|[a-z]+/).map { |part| part.match?(/\d/) ? [0, part.to_i, ""] : [1, 0, part] }
  end

  # Strip a `store:` prefix from a ref so a cross-store and same-store form compare.
  def bare_ref(ref)
    ref.to_s.include?(":") ? ref.to_s.split(":", 2).last : ref.to_s
  end

  # Extract bare-id wikilink refs from a body's `## Links` section. Matches
  # `[[<id>--<slug>|...]]` and `[[<store>:<id>--<slug>|...]]`, yielding the bare id.
  # Reads only the Links section so example fences elsewhere are not scanned.
  def links_refs(body)
    section = section_text(body, "Links")
    return [] if section.empty?

    section.scan(/\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/).filter_map do |match|
      t = bare_ref(match.first.strip)
      id = t.split("--", 2).first
      id unless id.nil? || id.empty?
    end.uniq
  end

  # The text under the first `## <heading>` heading, up to the next `## ` heading. A
  # deliberately small reader since we only need the section content. Fence lines are
  # skipped so a `## Links` (or any heading) inside an example block is ignored.
  def section_text(body, heading)
    lines = body.to_s.lines
    out = []
    capture = false
    in_fence = false
    lines.each do |line|
      stripped = line.strip
      if stripped.start_with?("```")
        in_fence = !in_fence
        next
      end
      next if in_fence

      if stripped == "## #{heading}"
        capture = true
        next
      end
      break if capture && stripped.start_with?("## ")

      out << line if capture
    end
    out.join.strip
  end

  # Append a ref to a frontmatter array (`sources` or `chain`), creating the key if
  # absent. Touches ONLY the frontmatter block; the body (including `## Links`) is
  # left byte-identical. Inline-flow arrays (`key: ["a", "b"]`) are extended in place;
  # an absent key is inserted before the closing `---`. Never deletes.
  def add_frontmatter_ref(content, key, ref)
    return content unless content.start_with?("---")

    parts = content.split("---", 3)
    return content if parts.length < 3

    fm = parts[1]
    line_re = /^#{Regexp.escape(key)}:\s*(.*)$/
    if fm =~ line_re
      current = Regexp.last_match(1).strip
      new_line = extend_flow_array(key, current, ref)
      fm = fm.sub(line_re, new_line)
    else
      fm = fm.rstrip + "\n#{key}: [\"#{ref}\"]\n"
    end
    "---#{fm}---#{parts[2]}"
  end

  def extend_flow_array(key, current, ref)
    if current.empty? || current == "[]"
      %(#{key}: ["#{ref}"])
    elsif current.start_with?("[") && current.end_with?("]")
      inner = current[1..-2].strip
      inner.empty? ? %(#{key}: ["#{ref}"]) : %(#{key}: [#{inner}, "#{ref}"])
    else
      %(#{key}: ["#{ref}"])
    end
  end
end
