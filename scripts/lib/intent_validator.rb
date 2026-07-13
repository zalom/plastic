# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "date"
require "time"

# IntentValidator — the single source of truth for "is an intent born complete?"
# (intent 60).
#
# An intent is born complete when its frontmatter carries every required field
# and its `sources` and `chain` are well-formed arrays of Folgezettel id references
# (bare ids like `1a2`, or cross-store refs like `global:1a2`; integer ids are coerced).
# This module is the only definition of that contract; the `validate-intent` CLI,
# the doctor diagnostics, and the creating-intent skill all consult it so the
# definition never drifts across copies.
#
# Pure and dependency-injected: `validate` accepts an injectable `plastic_home`
# for house-style parity, parses with a rescue-to-safe-default reader, uses no
# `eval`, and performs no file writes and no global-constant injection.
module IntentValidator
  module_function

  # Must match Doctor::REQUIRED_FRONTMATTER_FIELDS (scripts/doctor.rb).
  REQUIRED_FIELDS = %w[id intent sources chain created author tags].freeze

  # Fields whose value must be a well-formed array of valid id strings.
  ARRAY_ID_FIELDS = %w[sources chain].freeze

  # Sanctioned top-level intent sections, in order (intent 60b). The only
  # sanctioned `###` subsection is `### Decisions`, which is OPTIONAL (added after
  # brainstorming) and therefore never flagged as missing. This is the single
  # definition shared by the create gate, the validate-intent CLI, and doctor.
  SANCTIONED_SECTIONS = ["## Intent", "## Context", "## Outcome", "## Insights", "## Links"].freeze

  # Folgezettel id form: digits then an optional lowercase-letter/digit suffix
  # (for example "14", "14a", "4a1"). Mirrors scripts/folgezettel-id.
  ID_PATTERN = /\A([a-z0-9-]+:)?\d+[a-z0-9]*\z/

  # True iff `value` is a String matching the Folgezettel id form. When `known_stores` is
  # given (an Array of store slugs, e.g. from StoreDiscovery.known_slugs), a cross-store
  # prefix must also name a store in that set; a bare id (no prefix) is unaffected. When
  # `known_stores` is nil (the default), only the shape is checked, so every existing
  # caller keeps working unchanged (intent 189 D3).
  def valid_id?(value, known_stores: nil)
    s = value.to_s
    return false unless s.match?(ID_PATTERN)
    return true if known_stores.nil?

    prefix = s[/\A([a-z0-9-]+):/, 1]
    prefix.nil? || known_stores.include?(prefix)
  end

  # Read a file's YAML frontmatter, returning the parsed Hash (or {} when the
  # frontmatter block is empty), or nil when there is no parseable frontmatter.
  # A copy of Doctor#parse_frontmatter so `created:` dates do not crash.
  def parse_frontmatter(path)
    return nil unless File.exist?(path)

    parse_frontmatter_text(File.read(path))
  rescue StandardError
    nil
  end

  # PURE: parse YAML frontmatter from a content STRING (no file IO). Returns the
  # parsed Hash, {} for an empty block, or nil when there is no parseable block.
  def parse_frontmatter_text(content)
    return nil unless content.is_a?(String) && content.start_with?("---")

    parts = content.split("---", 3)
    return nil if parts.length < 3

    YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
  rescue StandardError
    nil
  end

  # PURE: strip the leading YAML frontmatter block from a content STRING,
  # returning the body text (everything after the closing `---`). When there is
  # no frontmatter block, the whole content is the body.
  def body_of(content)
    return "" unless content.is_a?(String)
    return content unless content.start_with?("---")

    parts = content.split("---", 3)
    parts.length < 3 ? content : parts[2]
  end

  # PURE: given the intent file body text, return sanctioned-section findings.
  # Flags any unknown top-level `## ` heading and any missing sanctioned section.
  # Ignores `### ` subsections entirely (Decisions is optional and lives under
  # Context). Returns { ok:, missing: [section names], unknown: [heading strings] }.
  def validate_sections(body)
    headings = body.to_s.lines.filter_map do |l|
      s = l.strip
      s if s.start_with?("## ") && !s.start_with?("### ")
    end
    present = headings & SANCTIONED_SECTIONS
    missing = SANCTIONED_SECTIONS - present
    unknown = headings - SANCTIONED_SECTIONS
    { ok: missing.empty? && unknown.empty?, missing: missing, unknown: unknown }
  end

  # PURE: given a parsed frontmatter Hash (or nil), return
  # { ok: Boolean, missing: [field names], errors: [human strings] }. `known_stores`
  # (optional, an Array of store slugs) is forwarded to valid_id? for each array-field
  # element; when nil, only id shape is checked (unchanged existing behavior).
  def validate_frontmatter(fm, known_stores: nil)
    unless fm.is_a?(Hash)
      return { ok: false, missing: REQUIRED_FIELDS.dup, errors: ["no frontmatter found"] }
    end

    missing = REQUIRED_FIELDS.reject { |f| fm.key?(f) }
    errors = missing.map { |f| "missing required field: #{f}" }

    ARRAY_ID_FIELDS.each do |key|
      next unless fm.key?(key)

      value = fm[key]
      unless value.is_a?(Array)
        errors << "#{key} must be an array"
        next
      end

      value.each do |element|
        next if valid_id?(element, known_stores: known_stores)

        errors << id_error(key, element, known_stores)
      end
    end

    { ok: missing.empty? && errors.empty?, missing: missing, errors: errors }
  end

  # Build the rejection message for one bad id. Distinguishes a shape failure (never a
  # valid Folgezettel form at all) from a known-store rejection (right shape, but the
  # store prefix names a store that does not exist), so an agent can tell "typo'd id" apart
  # from "made up a store" (intent 189 D3).
  def id_error(key, element, known_stores)
    s = element.to_s
    prefix = known_stores && s.match?(ID_PATTERN) ? s[/\A([a-z0-9-]+):/, 1] : nil
    if prefix
      "#{key} has invalid id: #{element.inspect} (store #{prefix.inspect} is not a known " \
        "store; known stores: #{known_stores.sort.join(", ")})"
    else
      "#{key} has invalid id: #{element.inspect}"
    end
  end

  # PURE: combine the frontmatter result with section-structure findings for a
  # content STRING. Returns the frontmatter result hash extended with
  # :section_missing, :section_unknown, and folded section errors; :ok is the AND
  # of frontmatter and sections. Lets the create gate validate proposed content
  # (no file on disk) with the same definition as the CLI and doctor.
  def validate_content(content, known_stores: nil)
    fm_result = validate_frontmatter(parse_frontmatter_text(content), known_stores: known_stores)
    sections = validate_sections(body_of(content))
    merge_sections(fm_result, sections)
  end

  # Fold section findings into a frontmatter result hash (shared by validate and
  # validate_content). Does not mutate the input.
  def merge_sections(fm_result, sections)
    errors = fm_result[:errors].dup
    sections[:unknown].each { |h| errors << "unknown section: #{h}" }
    sections[:missing].each { |s| errors << "missing required section: #{s}" }
    {
      ok: fm_result[:ok] && sections[:ok],
      missing: fm_result[:missing],
      errors: errors,
      section_missing: sections[:missing],
      section_unknown: sections[:unknown],
    }
  end

  # Resolve an intent directory's primary md file and validate its frontmatter
  # AND its sanctioned section structure. `plastic_home` is accepted for
  # house-style parity (injectable) even though validation reads the dir directly.
  def validate(intent_dir, plastic_home: File.join(Dir.home, ".plastic"), known_stores: nil)
    md_path = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    content = File.exist?(md_path) ? File.read(md_path) : nil
    validate_content(content, known_stores: known_stores)
  end

  # PURE: cross-intent graph-shape invariants (intent 68). These need visibility
  # over the whole intent set, so they live apart from the single-file born-complete
  # helpers above (which must not drift). No file IO: the caller builds `nodes`.
  #
  # `nodes` is a Hash { id(String) => { sources: [ids], chain: [ids] } } for every
  # intent in ONE store's id space. Returns { i1: [...], i3: [...], i4: [...] },
  # each an array of human-readable finding strings.
  #
  # I2 (no false symmetry) is INTENTIONALLY not computed: a relational `chain` entry
  # with no reciprocal `sources` is valid and must never be flagged.
  def validate_graph(nodes)
    nodes = normalize_nodes(nodes)
    { i1: graph_i1(nodes), i3: graph_i3(nodes), i4: graph_i4(nodes) }
  end

  # Coerce node arrays to deduped String id lists; tolerate missing keys.
  def normalize_nodes(nodes)
    return {} unless nodes.is_a?(Hash)

    nodes.each_with_object({}) do |(id, edges), acc|
      edges = {} unless edges.is_a?(Hash)
      acc[id.to_s] = {
        sources: Array(edges[:sources] || edges["sources"]).map(&:to_s).uniq,
        chain: Array(edges[:chain] || edges["chain"]).map(&:to_s).uniq,
      }
    end
  end

  # An id is a cross-store reference (out of this store's scope) when it carries a
  # `<store>:` prefix, mirroring how `valid_id?` accepts the prefix. Such refs are
  # resolved outside this node set, so they are never danglers here.
  def cross_store_ref?(id)
    id.to_s.include?(":")
  end

  # I1 (formative reciprocity): for every B and every `s` in B.sources that resolves
  # in this store, B must appear in s.chain. A `s` that does not resolve is an I4
  # dangler, not an I1 violation, so it is skipped here.
  def graph_i1(nodes)
    findings = []
    nodes.each do |b_id, edges|
      edges[:sources].each do |s|
        next if cross_store_ref?(s)
        next unless nodes.key?(s)

        findings << "#{b_id}.sources lists #{s} but #{s}.chain is missing #{b_id}" unless nodes[s][:chain].include?(b_id)
      end
    end
    findings
  end

  # I3 (per-node disjoint): X.sources and X.chain must not overlap.
  def graph_i3(nodes)
    findings = []
    nodes.each do |x_id, edges|
      (edges[:sources] & edges[:chain]).each do |overlap|
        findings << "#{x_id} lists #{overlap} in BOTH sources and chain"
      end
    end
    findings
  end

  # I4 (no danglers): every bare (same-store) id in any sources/chain must resolve
  # to a node. Cross-store `<store>:<id>` refs resolve elsewhere and are not flagged.
  def graph_i4(nodes)
    findings = []
    nodes.each do |id, edges|
      %i[sources chain].each do |field|
        edges[field].each do |ref|
          next if cross_store_ref?(ref)
          next if nodes.key?(ref)

          findings << "#{id}.#{field} references #{ref} which resolves to no intent"
        end
      end
    end
    findings
  end
end
