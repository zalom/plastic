# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "date"

# NodeFile (intent 334, n3): one node file's YAML envelope (`node`, `kind`,
# `files`, `budget`) over a Markdown body, plus the deterministic id minter
# (327 D1r, D5r, D9r-D12r, D16r). The kind-prefix rule lives here, not in
# GraphEdges, which stays loose about id grammar so a numeric roadmap id
# parses the same way (D12r).
#
# Pure and side-effect-free: parse reads one file and returns a Result hash,
# never raising across the boundary; mint_id takes the ids already present
# and returns one past the highest of them. Reserving an id against a
# concurrent minter is G7's problem, not a claim this module makes (D16r);
# gathering the ids an intent has ever seen is NodeIds' job (335a), which is
# why this module still requires nothing but yaml and date.
module NodeFile
  module_function

  KIND_PREFIX = { "work" => "n", "verify" => "v", "decision" => "d", "research" => "r" }.freeze
  VALID_KINDS = KIND_PREFIX.keys.freeze
  FENCE_LINE_RE = /\A\s{0,3}(`{3,}|~{3,})/.freeze

  # {ok:, node:, kind:, files:, budget:, body:, errors:}. `body` is the raw
  # text after the frontmatter block, present even when `ok` is false and the
  # body itself parsed fine, so a caller can still inspect sections on an
  # envelope-invalid file. Every failure mode returns errors rather than
  # raising: a missing file, absent or non-mapping frontmatter, or YAML that
  # will not parse.
  def parse(path)
    return failure(["node file not found: #{path}"]) unless File.exist?(path)

    content = File.read(path)
    return failure(["missing YAML frontmatter"]) unless content.start_with?("---")

    parts = content.split("---", 3)
    return failure(["missing YAML frontmatter"]) if parts.length < 3

    fm = begin
      YAML.safe_load(parts[1], permitted_classes: [Date, Time])
    rescue StandardError => e
      return failure(["frontmatter is not valid YAML: #{e.message}"])
    end
    fm = {} if fm.nil?
    return failure(["frontmatter must be a mapping, got #{fm.class}"]) unless fm.is_a?(Hash)

    body = parts[2].to_s
    errors = []

    kind = fm["kind"].to_s
    unless VALID_KINDS.include?(kind)
      errors << "unknown kind: #{fm["kind"].inspect} (must be one of #{VALID_KINDS.join(', ')})"
    end

    id = fm["node"].to_s
    errors << "missing node id (node:)" if id.empty?

    if !id.empty?
      basename = File.basename(path, ".md")
      unless filename_matches_id?(basename, id)
        errors << "node id #{id.inspect} does not match filename #{File.basename(path).inspect}"
      end
    end

    if !id.empty? && VALID_KINDS.include?(kind)
      expected_prefix = KIND_PREFIX[kind]
      unless id.match?(/\A#{Regexp.escape(expected_prefix)}[1-9][0-9]*\z/)
        errors << "node id #{id.inspect} does not match kind #{kind.inspect}'s prefix #{expected_prefix.inspect}"
      end
    end

    errors << "depends_on: is not a valid envelope field (removed by 327 D41; edges belong in ## Graph)" if fm.key?("depends_on")
    errors << "turns: is not a valid envelope field (removed by 327 D47)" if fm.key?("turns")

    files = fm["files"]
    if files.nil?
      errors << "missing files:"
    elsif !files.is_a?(Array)
      errors << "files: must be a list, got #{files.class}"
    end

    budget, budget_errors = normalize_budget(fm["budget"])
    errors.concat(budget_errors)

    {
      ok: errors.empty?,
      node: id.empty? ? nil : id,
      kind: kind.empty? ? nil : kind,
      files: files.is_a?(Array) ? files : nil,
      budget: budget,
      body: body,
      errors: errors,
    }
  end

  def failure(errors)
    { ok: false, node: nil, kind: nil, files: nil, budget: nil, body: nil, errors: errors }
  end

  # <id>.md or <id>--<slug>.md, exactly - a longer id's file (n11--x.md) must
  # never satisfy a shorter id (n1), so the id is matched as the whole prefix
  # up to end-of-string or the literal "--" separator, never as a substring
  # (fold A9).
  def filename_matches_id?(basename, id)
    basename.match?(/\A#{Regexp.escape(id)}(--[A-Za-z0-9][A-Za-z0-9-]*)?\z/)
  end

  # budget: normalizes to a plain integer token ceiling. A bare integer and
  # {tokens: N} both normalize to N; {turns: N} is the field 327 D47 removed
  # and is a named error, never silently accepted (fold: report's example).
  def normalize_budget(raw)
    return [nil, []] if raw.nil?
    return [raw, []] if raw.is_a?(Integer)

    if raw.is_a?(Hash)
      return [nil, ["budget: {turns:} was removed by 327 D47; use budget: <int> or {tokens: <int>}"]] if raw.key?("turns") || raw.key?(:turns)

      tokens = raw["tokens"] || raw[:tokens]
      return [tokens, []] if tokens.is_a?(Integer)

      return [nil, ["budget: must normalize to an integer token count, got #{raw.inspect}"]]
    end

    [nil, ["budget: must be an integer or {tokens: <int>}, got #{raw.class}"]]
  end

  # Every [heading_line, body] pair in the body text, split on any heading
  # line, fence-aware: a "#" line inside a fenced block never starts a new
  # section (fold: "a node passes on a section it does not have").
  def split_by_headings(text)
    sections = []
    heading = nil
    body = +""
    each_fence_line(text) do |line, fenced|
      if !fenced && line.start_with?("#")
        sections << [heading, body] if heading
        heading = line.strip
        body = +""
      else
        body << line
      end
    end
    sections << [heading, body] if heading
    sections
  end

  # Markdown table data rows (header + separator stripped) in text, fence-aware.
  def table_rows(text)
    lines = []
    each_fence_line(text) do |line, fenced|
      next if fenced

      stripped = line.strip
      lines << stripped if stripped.start_with?("|")
    end
    sep_idx = lines.index { |l| l.match?(/\A\|[\s:|-]+\|?\z/) }
    return [] unless sep_idx

    lines[(sep_idx + 1)..].map { |l| l.split("|", -1).map(&:strip)[1..-2].to_a }
  end

  def each_fence_line(text)
    return enum_for(:each_fence_line, text) unless block_given?

    marker = nil
    text.to_s.each_line do |line|
      if marker
        yield line, true
        m = line.match(FENCE_LINE_RE)
        next unless m && m[1][0] == marker[0] && m[1].length >= marker[1]
        next unless line.sub(FENCE_LINE_RE, "").strip.empty?

        marker = nil
      else
        m = line.match(FENCE_LINE_RE)
        if m
          marker = [m[1][0], m[1].length]
          yield line, true
        else
          yield line, false
        end
      end
    end
  end

  # One past the highest id ever seen for the kind: purely numeric, so ids
  # never sort as strings ("n10" ranking above "n9"), and a gap in the
  # sequence STAYS a gap.
  #
  # Node ids never recycle (335a, owner ruling 2026-09-09). Intent 335 keyed
  # the work ledger in savepoint.md on node id, and deletion is not a
  # transition, so nothing in the ledger says a node is gone. Reissuing a
  # deleted node's id therefore hands the new node the dead one's whole
  # history: its `done` line, its evidence, its holder, and the successors
  # that line released. The failure is silent, which is the worst shape it
  # could take, so the gap is a headstone rather than free space.
  #
  # `taken` may carry ids this kind's grammar rejects, because NodeIds
  # over-reserves on purpose (335a D11); they are ignored without shifting
  # the sequence.
  def mint_id(kind, taken)
    prefix = KIND_PREFIX[kind.to_s]
    return nil unless prefix

    used = taken.to_a.filter_map do |id|
      m = id.to_s.match(/\A#{Regexp.escape(prefix)}([1-9][0-9]*)\z/)
      m && m[1].to_i
    end

    "#{prefix}#{(used.max || 0) + 1}"
  end
end
